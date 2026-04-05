import api/server
import api/types.{type Paginated, type Record, type ListReq, type CreateReq, type UpdateReq, type ReadReq, type DeleteReq, type Action, SocketReq, Updated, Deleted, Created, type Sub, type SocketResp,}
import api/types/id.{Id}
import app/types.{type PubSub} as app
import app/user
import bravo
import bravo/uset
import fpo/api/erl/server.{type Server, Server, type Msg} as erl_server
import fpo/monad/app.{subscribe, broadcast, run, pure} as _
import fpo/types as fpo
import fpo/types/err.{type Err}
import gleam/erlang/process.{type Selector}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None}
import gleam/pair
import gleam/result
import gleam/set.{type Set}
import gleam/time/timestamp
import mist
import shared/api.{type Item, type ItemAttr} as api
import youid/uuid.{type Uuid}

pub fn start(
  req req: Request(mist.Connection),
  ctx ctx: fpo.Context(config, pubsub, user),
  server server: Server(api, fpo.Context(config, pubsub, user))
) -> Response(mist.ResponseData) {
  erl_server.start(req:, ctx:, server:)
}

//

pub type Context = fpo.Context(app.Config, app.PubSub, user.User)

// codegen server

pub fn api_server() -> Server(api.Api, Context) {
  Server(
    call: call_api_server,
    decoder: api.decoder_api(),
  )
}

fn call_api_server(
  req req: types.SocketReq(api.Api),
  ctx ctx: Context,
  subs subs: Set(String),
  send send: fn(SocketResp) -> Msg
) -> #(Set(String), SocketResp, Option(Selector(Msg))) {
  let SocketReq(ref:, req:) = req

  case req {
    api.Items(crud:) -> {
      crud_items()
      |> server.process_crud(crud:, ref:, ctx:)
      |> fn(resp) {
        #(subs, resp, None)
      }
    }

    api.IntToString(func:) -> {
      func_int_to_string()
      |> server.process_func(func:, ref:, ctx:)
      |> fn(resp) {
        #(subs, resp, None)
      }
    }

    api.SubscribeToItems(sub:) -> {
      sub_subscribe_to_items(sub:, send:)
      |> server.process_sub(sub:, ref:, ctx:, subs:)
    }
  }
}

// domain server impl

pub fn func_int_to_string() -> server.FuncHandler(Int, String, Context) {
  server.FuncHandler(
    run: int_to_string,
    //
    encode: json.string,
  )
}

fn int_to_string(
  num num: Int,
  ctx _ctx: fpo.Context(config, pubsub, user),
) -> Result(String, types.Err) {
  Ok(int.to_string(num))
}

pub fn crud_items() -> server.CrudHandler(Item, Item, Item, ItemAttr, Context) {
  server.CrudHandler(
    list: list_items,
    // list: list_items_app |> app_to_func(err: function.identity),
    create: create_items,
    update: update_items,
    read: read_items,
    delete: delete_items,
    //
    encode: api.encode_item,
  )
}

fn list_items(
  req _req: ListReq(Item, key),
  ctx ctx: Context,
) -> Result(Paginated(Item), types.Err) {
  let assert Ok(items) =
    uset.tab2list(ctx.cfg.items)

  let items =
    items
    |> list.map(pair.second)

  let pagination = types.Pagination(0, 0) // TODO next
  Ok(types.Paginated(resources: items, pagination:))
}
fn create_items(
  req req: CreateReq(Item, Item),
  ctx ctx: Context,
) -> Result(Record(Item), types.Err) {
  let id = Id(uuid.v7_string())
  let ts = timestamp.system_time()
  let item = types.Record(id:, created_at: ts, updated_at: ts, resource: req.data)
  let assert Ok(_inserted) = ctx.cfg.items |> uset.insert(item.id, item)
  let _broadcasted = broadcast_item(item:, action: Created, ctx:)
  Ok(item)
}
fn update_items(
  req req: UpdateReq(Item, Item),
  ctx ctx: Context,
) -> Result(Record(Item), types.Err) {
  case uset.lookup(ctx.cfg.items, req.id) {
    Error(err) ->
      case err {
        bravo.Empty ->
          Error(types.Client(types.NotFound(req.id.id, None)))

        _ ->
          todo
      }

    Ok(types.Record(resource: item, ..) as record) -> {
      let updated_at = timestamp.system_time()
      let item = api.Item(..item, name: req.data.name)
      let record = types.Record(..record, resource: item, updated_at:)
      let _broadcasted = broadcast_item(item: record, action: Updated, ctx:)
      Ok(record)
    }
  }
}
fn read_items(
  req req: ReadReq(Item),
  ctx ctx,
) -> Result(Record(Item), types.Err) {
  todo
}
fn delete_items(
  req req: DeleteReq(Item),
  ctx ctx: Context,
) -> Result(Record(Item), types.Err) {
  case uset.lookup(ctx.cfg.items, req.id) {
    Error(err) ->
      case err {
        bravo.Empty ->
          Error(types.Client(types.NotFound(req.id.id, None)))
        _ ->
          todo
      }

    Ok(item) -> {
      let assert Ok(_deleted) = uset.delete_key(ctx.cfg.items, item.id)
      let _broadcasted = broadcast_item(item:, action: Deleted, ctx:)
      Ok(item)
    }
  }
}

fn sub_subscribe_to_items(
  sub sub: Sub(api.ItemsSubMsg),
  send send: fn(SocketResp) -> Msg,
) -> server.SubHandler(api.ItemsSubMsg, Context, Selector(Msg), Msg) {
  server.SubHandler(
    run: subscribe_to_items,
    encode: api.encode_items_sub_msg,
    sub:,
    send:,
  )
}

fn sub_socket_resp(
  value value: t,
  ref ref: Uuid,
  encode encode: fn(t) -> Json,
) -> types.SocketResp {
  types.S(Ok(value))
  |> types.encode_subscription_msg(
    types.encode_result(_, encode, fn(_) { json.null() })
  )
  |> Ok
  |> types.SocketResp(ref:, action: None)
}

fn subscribe_to_items(
  _sub: Sub(msg),
  ref ref: Uuid,
  ctx ctx: Context,
  send send: fn(SocketResp) -> Msg, // TODO rename ... `wrap`?
) -> Result(Selector(Msg), types.Err) {
  let _ = subscribe(
    to: "items",
    in: fn(rs: PubSub) { rs.items },
    wrap: fn(t) {
      api.ItemsSubMsg(item: t.0, action: t.1)
      |> sub_socket_resp(ref:, encode: api.encode_items_sub_msg)
      |> send
    }
  )
  |> run(ctx, Nil)
  |> result.replace_error(types.Server(types.ServerErr("failed to subscribe (`" <> "subscribe_to_items" <> "`)")))
}

fn broadcast_item(
  item item: Record(api.Item),
  action action: Action,
  ctx ctx: Context,
) -> Result(Nil, Err(err)) {
  {
    use <- broadcast(
      in: fn(rs: PubSub) { rs.items },
      to: "items",
      msg: #(item, action),
    )
    pure(Nil)
  }
  |> run(ctx, Nil)
}
