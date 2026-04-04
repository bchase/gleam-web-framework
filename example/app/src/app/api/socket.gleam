import gleam/set.{type Set}
import bravo
import bravo/uset
import gleam/pair
import gleam/int
import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import app/user
import gleam/string
import gleam/io
import gleam/option.{type Option, Some, None}
import gleam/result
import gleam/list
import youid/uuid.{type Uuid}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json.{type Json}
import gleam/time/timestamp.{type Timestamp}
import fpo/types/err.{type Err}
import fpo/types as fpo
import app/types.{type PubSub} as app
import mist
//
import lustre/effect.{type Effect}
//
import api.{type SocketResp, type Req, type Resp} as _
// import api/types.{SocketReq, SocketResp, type Record, type Action, Created, Updated, Deleted}
import api/types.{List, ListReq, Create, Read, Update, Delete, CreateReq, ReadReq, UpdateReq, DeleteReq, type Params, type Paginated, encode_paginated, encode_record, type Record, type ConfirmDelete, type ListReq, type Crud, type CreateReq, type UpdateReq, type ReadReq, type DeleteReq, SocketResp, type Func, type Action, SocketReq, Updated, Deleted, Created, type Sub}
import api/id.{type Id, Id}
import fpo/monad/app.{subscribe, broadcast, run, pure} as _
//
import api/server
import shared/api.{type Item, type ItemAttr} as api

pub type Context = fpo.Context(app.Config, app.PubSub, user.User)

pub fn start(
  req req: Request(mist.Connection),
  ctx ctx: Context,
) -> Response(mist.ResponseData) {
  mist.websocket(
    request: req,
    on_init: init(conn: _, ctx:),
    handler: update,
    on_close: close,
  )
}

type Msg {
  NoOp
  Broadcast(msg: SocketResp)
}

type Socket {
  Socket(
    self: Subject(Msg),
    ctx: Context,
    conn: mist.WebsocketConnection,
    subs: Set(String),
    // state: State,
  )
}

// //

// type Sub {
//   PersonChanged(
//     person: Person,
//     action: Action
//   )
// }

// type SubErr

// fn subscriptions(
//   msg msg: fn(List(Sub)) -> msg,
//   err err: fn(Err) -> msg,
// ) {
//   todo
// }

// fn subscribe(
//   sub sub: Sub,
//   msg msg: fn(List(Sub)) -> msg,
//   err err: fn(Err) -> msg,
// ) {
//   todo
// }

// fn unsubscribe(
//   sub sub: Sub,
//   msg msg: fn(List(Sub)) -> msg,
//   err err: fn(Err) -> msg,
// ) {
//   todo
// }

//

fn init(
  conn conn: mist.WebsocketConnection,
  ctx ctx: Context,
) -> #(Socket, Option(Selector(Msg))) {
  let self = process.new_subject()

  let selector: Selector(Msg) =
    process.new_selector()
    |> process.select(self)
    // |> process.select_map(self, fn(msg) {
    //   case msg {
    //   }
    // })
    // |> process.select_map(self, fn(msg) {
    //   case msg {
    //     mist.Text(..) -> NoOp
    //     mist.Binary(_) -> todo
    //     mist.Closed -> todo
    //     mist.Shutdown -> todo
    //     mist.Custom(_) -> todo
    //   }
    // })
    // |> process.select_map(self, ApiSocketMsg)

  #(Socket(self:, ctx:, conn:, subs: set.new()), Some(selector))
}

// fn init_items() -> Dict(Id(api.Item), Record(api.Item)) {
//   let ts = timestamp.unix_epoch
//   [
//     types.Record(
//       id: Id(uuid.v7_string()),
//       created_at: ts,
//       updated_at: ts,
//       resource: api.Item(name: "zzz"),
//     ),
//     types.Record(
//       id: Id(uuid.v7_string()),
//       created_at: ts,
//       updated_at: ts,
//       resource: api.Item(name: "aaa"),
//     ),
//   ]
//   // |> list.sort(fn(a, b) {
//   //   string.compare(a.resource.name, b.resource.name)
//   // })
//   |> list.map(fn(item: Record(api.Item)) {
//     #(item.id, item)
//   })
//   |> dict.from_list
// }

fn update(
  socket socket: Socket,
  msg msg: mist.WebsocketMessage(Msg),
  conn conn: mist.WebsocketConnection,
) -> mist.Next(Socket, Msg) {
  case msg {
    mist.Binary(_) -> {
      io.println_error("WEBSOCKET IGNORING BINARY MSG")
      mist.continue(socket)
    }

    mist.Text(msg) -> {
      serve(socket:, msg:, send:, send_resp: Broadcast, ctx: socket.ctx,
        get_subs: fn(socket: Socket) { socket.subs },
        set_subs: fn(socket: Socket, subs) { Socket(..socket, subs:) },
        get_self: fn(socket: Socket) { socket.self },
        server: Server(
          call: api_server,
          decoder: api.decoder_api(),
        ),
      )
    }

    mist.Custom(Broadcast(msg:)) -> {
      msg
      |> types.encode_socket_resp
      |> json.to_string
      |> send(socket)

      mist.continue(socket)
    }

    mist.Custom(NoOp) -> {
      mist.continue(socket)
    }

    mist.Closed | mist.Shutdown -> {
      let _ = close(socket:)

      mist.stop()
    }
  }
}

fn close(
  socket socket: Socket,
) -> Nil {
  Nil
}

type State {
  State(
    // people: List(Person),
    items: Dict(Id(api.Item), Record(api.Item)),
  )
}

// fn process(
//   socket socket: Socket,
//   req req: Req,
// ) -> #(Result(Resp, api.Err), Socket, Option(Selector(Msg))) {
//   let ctx = socket.ctx

//   case req {
//     api.ReqOther ->
//       todo

//     api.CrudItems(crud:) ->
//       case crud {
//         types.List(pagination: _) -> {
//           let assert Ok(items) =
//             uset.tab2list(socket.ctx.cfg.items)

//           let items =
//             items
//             |> list.map(pair.second)
//             |> types.ManyRecords(None)
//             |> api.GotItems

//           #(Ok(items), socket, None)
//         }

//         types.Create(new:) -> {
//           let ts = timestamp.system_time()
//           let item = types.Record(id: id.Id(uuid.v7_string()), created_at: ts, updated_at: ts, resource: new)

//           let _broadcasted =
//             broadcast_item(item:, action: Created, ctx: socket.ctx)

//           let assert Ok(_inserted) =
//             socket.ctx.cfg.items
//             |> uset.insert(item.id, item)

//           #(Ok(api.GotItem(item:, action: Created)), socket, None)
//         }

//         types.Update(id:, new:) -> {
//           case uset.lookup(socket.ctx.cfg.items, id) {
//             Error(err) ->
//               case err {
//                 bravo.Empty ->
//                   #(Error(types.Client(types.NotFound(id.id, None))), socket, None)
//                 _ ->
//                   todo
//               }

//             Ok(types.Record(resource: item, ..) as record) -> {
//               let updated_at = timestamp.system_time()
//               let item = api.Item(..item, name: new.name)
//               let record = types.Record(..record, resource: item, updated_at:)
//               let _broadcasted = broadcast_item(item: record, action: Updated, ctx: socket.ctx)
//               #(Ok(api.GotItem(item: record, action: Updated)), socket, None)
//             }
//           }
//         }

//         types.Delete(id:, confirm: _) -> {
//           case uset.lookup(socket.ctx.cfg.items, id) {
//             Error(err) ->
//               case err {
//                 bravo.Empty ->
//                   #(Error(types.Client(types.NotFound(id.id, None))), socket, None)
//                 _ ->
//                   todo
//               }

//             Ok(item) -> {
//               let assert Ok(_deleted) = uset.delete_key(socket.ctx.cfg.items, item.id)
//               let _broadcasted = broadcast_item(item:, action: Deleted, ctx: socket.ctx)
//               #(Ok(api.GotItem(item:, action: Deleted)), socket, None)
//             }
//           }
//         }

//         types.Get(id:) -> todo
//       }

//     api.Subscribe(subs:) -> {
//       let added =
//         case dict.is_empty(subs) {
//           True ->
//             None

//           False -> {
//             let selector =
//               process.new_selector()
//               |> process.select(process.new_subject())
//               // |> todo

//             subs
//             |> dict.to_list
//             |> list.fold(#(dict.new(), selector), fn(acc, t) {
//               let #(ref, sub) = t
//               let #(subs, selector) = acc

//               let result =
//                 case sub {
//                   api.SubItem(id:) -> todo
//                   api.SubItems -> {
//                     subscribe(
//                       to: "items",
//                       in: fn(rs: PubSub) { rs.items },
//                       wrap: fn(t) {
//                         let #(item, action) = t
//                         Broadcast(ref:, resp: api.GotItem(item:, action:))
//                       })
//                     |> run(ctx, Nil)
//                     // |> result.map(fn(selector) {
//                     //   selector
//                     //   // |> process.map_selector(fn(msg) {
//                     //   //   todo as "get `msg` this into the actor"
//                     //   // })
//                     // })
//                   }
//                 }

//               case result {
//                 Ok(new_selector) -> {
//                   let selector =
//                     selector
//                     |> process.merge_selector(new_selector)
//                     // |> todo

//                   #(dict.insert(subs, ref, sub), selector)
//                 }

//                 Error(err) -> {
//                   io.println_error("Failed to subscribe:")
//                   io.println_error(sub |> string.inspect)
//                   io.println_error(err |> string.inspect)
//                   acc
//                 }
//               }
//             })
//             |> Some
//           }
//         }

//       case added {
//         None ->
//           #(Ok(api.SubscribedTo(all_subs: socket.subs)), socket, None)

//         Some(#(subs, selector)) -> {
//           let socket =
//             Socket(..socket, subs: {
//               socket.subs
//               |> dict.merge(subs)
//               // |> list.append(subs)
//             })

//           #(Ok(api.SubscribedTo(all_subs: socket.subs)), socket, Some(selector))
//         }
//       }
//     }
//   }
// }

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
  socket socket: Socket,
) -> mist.Next(Socket, Msg) {
  case mist.send_text_frame(socket.conn, msg) {
    Ok(Nil) ->
      Nil

    Error(err) -> {
      io.println_error("SOCKET SEND ERR:")
      io.println_error(err |> string.inspect)
    }
  }

  mist.continue(socket)
}

// fn decoder_socket_req() -> Decoder(SocketReq) {
//   todo
// }

// fn decoder_req() -> Decoder(Req) {
//   todo
// }

// fn decoder_socket_resp() -> Decoder(SocketResp) {
//   todo
// }

// fn decoder_resp() -> Decoder(Resp) {
//   todo
// }

// fn encode_resp(
//   ref ref: Uuid,
//   resp resp: Resp,
// ) -> Json {
//   todo
// }

// // api

// pub type SocketReq {
//   SocketReq(
//     ref: Uuid,
//     req: Req,
//   )
// }

// pub type Req {
//   ReqPeople(
//     req: Crud(Person)
//   )
// }

// pub type SocketResp {
//   SocketResp(
//     ref: Uuid,
//     result: Result(String, Err)
//   )
// }

// pub type Resp {
//   RespPeople(
//     resp: Got(Person),
//   )
// }

// domain

// pub type Person {
//   Person(
//     id: Id(Person),
//     name: String,
//   )
// }

// // generic

// pub type Err {
//   NotFound(id: String)
//   RespDecodeErr(err: String)
//   RespWrongDecode(expected: String, got: String)
//   Err(err: String)
// }

// pub type Id(resource) {
//   Id(id: String)
// }

// pub type CrudPlus(resource, msg) {
//   Crud(Crud(resource))
//   Custom(msg)
// }

// pub type Crud(resource) {
//   List
//   Get(
//     id: Id(resource),
//   )
//   Create(
//     name: String,
//   )
//   Update(
//     id: Id(resource), name: String,
//   )
//   Delete(
//     id: Id(resource),
//   )
// }

// pub type Action {
//   Created
//   Updated
//   Deleted
// }

// pub type GotResult(resource) = Result(Got(resource), Err)

// pub type Got(resource) {
//   GotMany(
//     payload: List(resource),
//   )
//   GotOne(
//     payload: resource,
//     action: Option(Action),
//   )
// }

// fn decoder_person() -> Decoder(Person) {
//   todo
// }

// client helpers

// fn list_people(
//   socket socket: ws.WebSocket,
//   msg msg: fn(List(Person)) -> msg,
//   err err: fn(Err) -> msg,
// ) -> Effect(Nil) {
//   effect.from(fn(dispatch) {
//     // todo this doesn't work, because there's no way to assoc send w/ recv
//     //      orig ref/uuid approach might be needed...

//     // TODO async

//     ReqPeople(List)
//     |> ws.send(socket, _)

//     // dispatch(None)

//     todo
//   })
// }

// client

// type ClientState {
//   ClientState(
//     listeners: Dict(Uuid, fn(Result(Resp, Err)) -> ClientMsg),
//     people: List(Person),
//   )
// }

// type ClientMsg {
//   FetchPeople
//   // GotResp(resp: SocketResp)
//   GotPeople(people: List(Person))
// }

// fn listen_for(
//   ref ref: Uuid,
//   err err: fn(Err) -> ClientMsg,
//   msg msg: fn(Resp) -> ClientMsg,
// ) {
// }

// fn client_update(
//   model model: ClientState,
//   msg msg: ClientMsg,
// ) -> #(ClientState, Effect(ClientMsg)) {
//   case msg {
//     FetchPeople -> {
//       #(model, effect.none())
//     }

//     GotPeople(people:) -> {
//       #(ClientState(..model, people:), effect.none())
//     }

//     // GotResp(resp: SocketResp(ref:, result: Error(err))) -> {
//     //   model
//     // }

//     // GotResp(resp: SocketResp(ref:, result: Ok(json))) -> {
//     //   case json.parse(json, decoder_resp()) {
//     //     Ok(_) -> todo
//     //     Error(_) -> todo
//     //   }
//     // }
//   }
// }

// //

// // fn list(
// //   result result: Result(String, Err),
// //   decoder decoder: Decoder(t),
// // ) -> Result(t, Err) {
// //   case result {
// //     Ok(json) ->
// //       json
// //       |> json.parse(decoder)
// //       |> result.map_error(string.inspect)
// //       |> result.map_error(RespDecodeErr)

// //     Error(err) ->
// //       Error(err)
// //   }
// // }

// // fn list_people_(
// //   ref ref: Uuid,
// //   result result: Result(SocketResp, Err),
// // ) -> Result(Result(List(Person), Err), Nil) {
// //   list(ref:, result:, decoder: decode.list(decoder_person()))
// // }

// // fn list(
// //   ref ref: Uuid,
// //   result result: Result(SocketResp, Err),
// //   decoder decoder: Decoder(t),
// // ) -> Result(Result(t, Err), Nil) {
// //   case result {
// //     Ok(SocketResp(ref: resp_ref, result: Ok(json))) if resp_ref == ref ->
// //       case json.parse(json, decoder) {
// //         Ok(x) ->
// //           Ok(Ok(x))

// //         Error(err) ->
// //           Ok(Error(RespDecodeErr(err: err |> string.inspect)))
// //       }

// //     Ok(SocketResp(ref: resp_ref, result: Error(err))) if resp_ref == ref ->
// //       Ok(Error(err))

// //     Ok(SocketResp(..)) ->
// //       Error(Nil)

// //     Error(err) ->
// //       Ok(Error(err))
// //   }
// // }

// // fn list_people(
// //   ref ref: Uuid,
// //   result result: Result(SocketResp, Err),
// // ) -> Result(Result(List(Person), Err), Nil) {
// //   case result {
// //     Ok(SocketResp(ref: resp_ref, result: Ok(json))) if resp_ref == ref ->
// //       case json.parse(json, decoder_resp()) {
// //         Ok(RespPeople(GotMany(payload:))) ->
// //           Ok(Ok(payload))

// //         Ok(resp) ->
// //           Ok(Error(RespWrongDecode(
// //             expected: "RespPeople(GotMany(..))",
// //             got: resp |> string.inspect,
// //           )))

// //         Error(err) ->
// //           Ok(Error(RespDecodeErr(err: err |> string.inspect)))
// //       }

// //     Ok(SocketResp(ref: resp_ref, result: Error(err))) if resp_ref == ref ->
// //       Ok(Error(err))

// //     Ok(SocketResp(..)) ->
// //       Error(Nil)

// //     Error(err) ->
// //       Ok(Error(err))
// //   }
// // }



// TODO mv `server`

type ApiServer(req, context) =
  fn(types.SocketReq(req), context, Set(String)) -> Result(SocketResp, types.Err)

type Server(req, context, msg) {
  Server(
    call: fn(types.SocketReq(req), context, Set(String), fn(SocketResp) -> msg) -> #(Set(String), SocketResp, Option(Selector(msg))),
    decoder: Decoder(req),
  )
}

fn serve(
  socket socket: socket,
  msg msg: String,
  ctx ctx: context,
  server server: Server(req, context, msg),
  send send: fn(String, socket) -> mist.Next(socket, msg),
  get_self get_self: fn(socket) -> Subject(msg),
  get_subs get_subs: fn(socket) -> Set(String),
  set_subs set_subs: fn(socket, Set(String)) -> socket,
  send_resp send_resp: fn(SocketResp) -> msg,
) -> mist.Next(socket, msg) {
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
      |> send(socket)

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
  ctx ctx: Context,
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

fn api_server(
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
      // |> fn(t) {
      //   let #(subs, resp, selector) = t
      //   // let selector =

      //   // #(subs, resp, Some(selector))
      //   todo
      // }
    }
  }
}
