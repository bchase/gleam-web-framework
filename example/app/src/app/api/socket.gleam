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
import fpo/types
import app/types as app
import lustre
import lustre/runtime/server/runtime
import lustre/server_component
import mist
//
import lustre/effect.{type Effect}
//
import api.{type SocketReq, type SocketResp, type Req, type Resp}
import api/generic.{SocketReq, SocketResp}
import api/id

pub type Context = types.Context(app.Config, app.PubSub, user.User)

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

type Msg = mist.WebsocketMessage(Nil)
// type Msg {
//   WebsocketMsg(msg: mist.WebsocketMessage(SocketReq))
//   ApiSocketMsg(msg: api.SocketReq)
// }

type Socket {
  Socket(
    // self: Subject(Msg),
    ctx: Context,
    conn: mist.WebsocketConnection,
    state: State,
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
  // let self = process.new_subject()
  // let selector =
  //   process.new_selector()
  //   |> process.select_map(self, ApiSocketMsg)
  // #(Socket(ctx:, conn:, state: State(items: [])), Some(selector))

  #(Socket(ctx:, conn:, state: State(items: init_items())), None)
}

fn init_items() -> List(generic.Record(api.Item)) {
  let ts = timestamp.unix_epoch
  [
    generic.Record(
      id: id.Id(uuid.v7_string()),
      created_at: ts,
      updated_at: ts,
      resource: api.Item(name: "hi"),
    )
  ]
}

fn update(
  socket socket: Socket,
  msg msg: mist.WebsocketMessage(Msg),
  conn conn: mist.WebsocketConnection,
) -> mist.Next(Socket, state) {
  case msg |> echo {
    mist.Binary(_) -> {
      io.println_error("WEBSOCKET IGNORING BINARY MSG")
      mist.continue(socket)
    }

    mist.Text(json) ->
      case json.parse(json, api.decoder_socket_req()) {
        Ok(generic.SocketReq(ref:, req:)) -> {
          let #(state, result) = process(state: socket.state, req:)

          api.socket_resp(ref:, result:)
          |> api.encode_socket_resp
          |> json.to_string
          |> ws_send(conn, _)

          mist.continue(Socket(..socket, state:))
        }

        Error(err) -> {
          // TODO send err to client
          io.println_error("WEBSOCKET REQ DECODE ERR:")
          io.println_error(err |> string.inspect)
          mist.continue(socket)
        }
      }


    mist.Custom(msg) -> {
      echo msg
      mist.continue(socket)
    }

    // mist.Custom(msg) -> {
    //   case msg {
    //     SocketReq(ref:, req:) -> {
    //       let #(state, result) = process(state: socket.state, req:)

    //       api.socket_resp(ref:, result:)
    //       |> api.encode_socket_resp
    //       |> json.to_string
    //       |> ws_send(conn: socket.conn, msg: _)

    //       mist.continue(Socket(..socket, state:))
    //     }
    //   }
    // }

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
    items: List(generic.Record(api.Item)),
  )
}

fn process(
  state state: State,
  req req: Req,
) -> #(State, Result(Resp, api.Err)) {
  let result =
    case req {
      api.CrudItems(crud:) ->
        case crud {
          generic.List(pagination: _) -> {
            // let ts = timestamp.unix_epoch
            // let items = state.items |> list.index_map(fn(x, i) {
            //   generic.Record(id: i |> int.to_string |> id.Id, created_at: ts, updated_at: ts, resource: x)
            // })
            Ok(state.items |> generic.GotMany |> api.RespItems)
          }

          generic.Get(id:) -> todo
          generic.Create(new:) -> todo
          generic.Update(id:, new:) -> todo
          generic.Delete(id:, confirm: _) -> todo
        }

      api.ReqOther ->
        todo
    }
    // case req {
    //   ReqPeople(req: Create(name:)) -> todo
    //   ReqPeople(req: Update(id:, name:)) -> todo
    //   ReqPeople(req: Delete(id:)) -> todo

    //   ReqPeople(req: Get(id:)) ->
    //     state.people
    //     // |> list.find(fn(person: Person) { person.id == id})
    //     // |> result.map(fn(person) { RespPeople(Ok(GotOne(person, None))) })
    //     // |> result.unwrap(RespPeople(Error(NotFound(id: id.id))))
    //     |> todo

    //   ReqPeople(req: List) ->
    //     // RespPeople(ref, Ok(GotMany(state.people)))
    //     todo
    // }

  #(state, result)
}

fn ws_send(
  conn conn: mist.WebsocketConnection,
  msg msg: String,
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
