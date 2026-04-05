import api/server
import api/types.{type Paginated, type Record, type ListReq, type CreateReq, type UpdateReq, type ReadReq, type DeleteReq, type Action, SocketReq, Updated, Deleted, Created, type Sub, type SocketResp,}
import api/types/id.{Id}
import app/types.{type PubSub} as app
import app/user
import bravo
import bravo/uset
import fpo/monad/app.{subscribe, broadcast, run, pure} as _
import fpo/types as fpo
import fpo/types/err.{type Err}
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/pair
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/time/timestamp
import mist
import shared/api.{type Item, type ItemAttr} as api
import youid/uuid.{type Uuid}

pub type Context = fpo.Context(app.Config, app.PubSub, user.User)

type Socket(config, pubsub, user) {
  Socket(
    self: Subject(Msg),
    ctx: fpo.Context(config, pubsub, user),
    subs: Set(String),
  )
}

pub opaque type Msg {
  NoOp
  Broadcast(msg: SocketResp)
}

pub fn start(
  req req: Request(mist.Connection),
  ctx ctx: Context,
) -> Response(mist.ResponseData) {
  start_(req:, ctx:, server: api_server())
}

pub fn start_(
  req req: Request(mist.Connection),
  ctx ctx: fpo.Context(config, pubsub, user),
  server server: Server(api, fpo.Context(config, pubsub, user))
) -> Response(mist.ResponseData) {
  mist.websocket(
    request: req,
    on_init: init(conn: _, ctx:),
    handler: fn(socket, msg, conn) {
      update(socket:, msg:, conn:, server:)
    },
    on_close: close,
  )
}

fn init(
  conn _conn: mist.WebsocketConnection,
  ctx ctx: fpo.Context(config, pubsub, user),
) -> #(Socket(config, pubsub, user), Option(Selector(Msg))) {
  let self = process.new_subject()

  #(Socket(self:, ctx:, subs: set.new()), Some(
    process.new_selector()
    |> process.select(self)
  ))
}

fn update(
  socket socket: Socket(config, pubsub, user),
  msg msg: mist.WebsocketMessage(Msg),
  conn conn: mist.WebsocketConnection,
  server server: Server(api, fpo.Context(config, pubsub, user))
) -> mist.Next(Socket(config, pubsub, user), Msg) {
  case msg {
    mist.Custom(msg) ->
      update_custom_msg(socket:, msg:, conn:)

    mist.Binary(msg) ->
      ignore_binary_msg_with_warning(socket:, msg:)

    mist.Text(msg) ->
      respond_to(socket:, msg:, conn:, server:)

    mist.Closed | mist.Shutdown ->
      stop_after_running_closed_callback(socket:, close:)
  }
}

fn update_custom_msg(
  socket socket: Socket(config, pubsub, user),
  msg msg: Msg,
  conn conn: mist.WebsocketConnection,
) {
  case msg {
    NoOp ->
      mist.continue(socket)

    Broadcast(msg:) -> {
      msg
      |> types.encode_socket_resp
      |> json.to_string
      |> send(conn)

      mist.continue(socket)
    }
  }
}

fn ignore_binary_msg_with_warning(
  socket socket: Socket(config, pubsub, user),
  msg msg: BitArray,
) -> mist.Next(Socket(config, pubsub, user), Msg) {
  io.println_error("[WARNING] websocket ignoring binary msg: " <> string.inspect(msg))
  mist.continue(socket)
}

fn respond_to(
  socket socket: Socket(config, pubsub, user),
  msg msg: String,
  conn conn: mist.WebsocketConnection,
  server server: Server(a, fpo.Context(config, pubsub, user)),
) -> mist.Next(Socket(config, pubsub, user), Msg) {
  serve(socket:, conn:, msg:, send:, send_resp: Broadcast, ctx: socket.ctx,
    get_subs: fn(socket: Socket(config, pubsub, user)) { socket.subs },
    set_subs: fn(socket: Socket(config, pubsub, user), subs) { Socket(..socket, subs:) },
    get_self: fn(socket: Socket(config, pubsub, user)) { socket.self },
    server:,
  )
}

fn stop_after_running_closed_callback(
  socket socket: Socket(config, pubsub, user),
  close close: fn(Socket(config, pubsub, user)) -> Nil,
) -> mist.Next(Socket(config, pubsub, user), Msg) {
  let _ = close(socket)
  mist.stop()
}

fn close(
  socket _socket: Socket(config, pubsub, user),
) -> Nil {
  Nil
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

fn send(
  msg msg: String,
  conn conn: mist.WebsocketConnection,
) -> Nil {
  case mist.send_text_frame(conn, msg) {
    Ok(Nil) ->
      Nil

    Error(err) -> {
      io.println_error("SOCKET SEND ERR:")
      io.println_error(err |> string.inspect)
    }
  }
}

// TODO mv `server`

pub type Server(req, context) {
  Server(
    call: fn(types.SocketReq(req), context, Set(String), fn(SocketResp) -> Msg) -> #(Set(String), SocketResp, Option(Selector(Msg))),
    decoder: Decoder(req),
  )
}

fn serve(
  socket socket: socket,
  conn conn: mist.WebsocketConnection,
  msg msg: String,
  ctx ctx: context,
  server server: Server(req, context),
  send send: fn(String, mist.WebsocketConnection) -> Nil,
  get_self get_self: fn(socket) -> Subject(Msg),
  get_subs get_subs: fn(socket) -> Set(String),
  set_subs set_subs: fn(socket, Set(String)) -> socket,
  send_resp send_resp: fn(SocketResp) -> Msg,
) -> mist.Next(socket, Msg) {
  case parse_socket_req(msg, server.decoder) {
    Ok(req) -> {
      let subs = get_subs(socket)
      let #(subs, resp, selector) = server.call(req, ctx, subs, send_resp)

      let selector =
        {
          use selector <- option.map(selector)
          selector
          |> process.select(get_self(socket))
        }

      resp
      |> types.encode_socket_resp
      |> json.to_string
      |> send(conn)

      let socket =
        socket
        |> set_subs(subs)

      case selector {
        None ->
          mist.continue(socket)

        Some(selector) ->
          socket
          |> mist.continue
          |> mist.with_selector(selector)
      }
    }

    Error(ParseErr) ->
      todo as "ParseErr"
  }
}

type ParseErr {
  ParseErr
}
fn parse_socket_req(
  json json: String,
  decoder decoder: Decoder(req),
) -> Result(types.SocketReq(req), ParseErr) {
  {
    let parse = fn(decoder) {
      use ref <- result.try(
        decode.at(["ref"], decode.string)
        |> json.parse(json, _)
        // |> result.replace_error(NoRef(json:))
        |> result.replace_error(Nil)
      )

      use ref <- result.try(
        uuid.from_string(ref)
        |> result.map_error(fn(err) {
          // RefParseFailure(ref:, err: err |> string.inspect)
          Nil
        })
      )

      use req <- result.try(
        decode.at(["req"], decode.dynamic)
        |> json.parse(json, _)
        // |> result.replace_error(RespNotFound(ref:, json:))
        |> result.replace_error(Nil)
      )

      Ok(#(ref, req))
    }

    case parse(json) {
      Ok(#(ref, dyn)) -> {
        let assert Ok(req) = decode.run(dyn, decoder)
        Ok(SocketReq(ref:, req:))
      }

      Error(_) -> todo
    }
  }
  |> result.replace_error(ParseErr)
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
  ctx ctx: fpo.Context(config, pubsub, user),
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

// codegen server

fn api_server() -> Server(api.Api, Context) {
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
