import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import plinth/browser/shadow
import plinth/javascript/global
import plinth/browser/document
import plinth/browser/element as dom_element
import lustre/element/keyed
import api/id.{type Id}
import lustre/event
import gleam/list
import gleam/result
import gleam/dict.{type Dict}
import gleam/string
import gleam/io
import gleam/option.{type Option, Some, None}
import gleam/json.{type Json}
import lustre/component
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import gleam/pair
import lustre/effect.{type Effect}
import lustre
import lustre_websocket.{type WebSocketEvent} as ws
import api.{type SocketResp}
import api/generic.{List, Create, Update, Delete, type Record, type Records, type Action, Created, Updated, Deleted, type Pagination, type Paginated}
import youid/uuid.{type Uuid}
import gleam/javascript/array
//
import api/client.{type ApiClient, type Api}

// gleam run -m lustre/dev build --no-html --minify

pub fn main() -> Nil {
  register_web_component()
}

const tag_name = "fpo-example-client-component"

fn register_web_component() -> Nil {
  let component = lustre.component(init, update, view, decoders())
  let assert Ok(_) = lustre.register(component, tag_name)

  Nil
}

fn decoders() -> List(component.Option(Msg)) {
  [
    // component.on_attribute_change("", fn(str) { Error(Nil) }),
    // component.on_property_change("", decode.string |> decode.map(msg)),
  ]
}

type Model {
  Model(
    conn: Option(ws.WebSocket),
    items: client.ApiData(Dict(Id(client.Item), Record(client.Item))),
    item: Option(Record(client.Item)),
    uuid: Uuid,
    //
    reqs: Dict(Uuid, ApiRespHandler),
    //
    client: ApiClient(Api, Model, Msg),
    //
    str: Option(Result(String, client.Err)),
  )
}

type ApiRespHandler {
  SetRemoteData(set: fn(Model, Result(api.Resp, api.Err)) -> Model)
  SendMsg(msg: fn(Result(api.Resp, api.Err)) -> Msg)
}

type Msg {
  NoOp
  // websockets
  RecvWebSocketEvent(event: WebSocketEvent)
  // ui
  Send(num: Int)
  GotItemForm(values: List(#(String, String)))
  SetItem(item: Option(Record(client.Item)))
  // api resps
  RecvIntToString(result: Result(String, client.Err))
  RecvItem(result: Result(#(Record(client.Item), Action), client.Err))

  // subs
  RecvItems(result: Result(Paginated(client.Item), client.Err))
  // RecvSubscription(ref: String, resp: api.Resp)

  // DeleteItem(id: Id(api.Item))
  // // api resps
}

fn init(_) -> #(Model, Effect(Msg)) {
  let client =
    client.init(
      get_client: fn(model: Model) { model.client },
      set_client: fn(model: Model, client) { Model(..model, client:) },
      get_send: fn(model: Model) {
        case model.conn {
          None -> None
          Some(conn) -> Some(ws.send(conn, _))
        }
      },
      encode: client.encode_api,
      on_no_conn: fn(_) { None },
    )

  Model(
    conn: None,
    items: client.NotAsked,
    item: None,
    uuid: uuid.v7(),
    //
    reqs: dict.new(),
    //
    client:,
    //
    str: None,
  )
  |> pair.new(effect.batch([
    ws.init(ws_url, RecvWebSocketEvent),
  ]))
}

const ws_url = "/ws/api"

// fn set_remote_data(
//   map map: fn(api.Resp) -> Result(t, Nil),
//   set set: fn(Model, RemoteData(t, api.Err)) -> Model,
// ) -> ApiRespHandler {
//   SetRemoteData(set: fn(model, result) {
//     case result {
//       Error(err) -> {
//         model |> set(Failure(err:))
//       }

//       Ok(resp) ->
//         case map(resp) {
//           Ok(data) ->
//             model |> set(Success(data:))

//           Error(Nil) -> {
//             io.println_error("Failed to map api result: " <> result |> string.inspect)
//             model
//           }
//         }
//     }
//   })
// }

fn send_msg(
  map map: fn(api.Resp) -> Result(t, Nil),
  msg msg: fn(Result(t, api.Err)) -> Msg,
) -> ApiRespHandler {
  SendMsg(msg: fn(result) {
    case result {
      Error(err) ->
        msg(Error(err))

      Ok(resp) ->
        case map(resp) {
          Ok(data) ->
            msg(Ok(data))

          Error(Nil) -> {
            io.println_error("Failed to map api result: " <> result |> string.inspect)
            NoOp // TODO conv to `Result(Msg, Nil)`
          }
        }
    }
  })
}

fn set_focus(
  id id: String,
) -> Effect(Msg) {
  effect.from(fn(_) {
    global.set_timeout(100, fn() {
      {
        use wc <- result.try(document.get_elements_by_tag_name(tag_name) |> array.to_list |> list.first)
        use sr <- result.try(shadow.shadow_root(wc))
        use el <- result.try(shadow.query_selector(sr, "#" <> id))
        Ok(dom_element.focus(el))
      }
      |> result.unwrap(Nil)
    })
    Nil
  })
}

fn update(
  model model: Model,
  msg msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    NoOp ->
      pure(model)

    Send(num:) ->
      model.client.send(model, client.req_int_to_string(num, RecvIntToString))

    RecvIntToString(result:) -> {
      pure(Model(..model, str: Some(result)))
    }

    // DeleteItem(id: item_id) -> {
    //   model
    //   |> send(
    //     req: api.CrudItems(Delete(item_id, generic.ConfirmDelete)),
    //     handler: send_msg(
    //       msg: RecvItem,
    //       map: fn(resp) {
    //         case resp {
    //           api.GotItem(item:, action:) -> Ok(#(item, action))
    //           _ -> Error(Nil)
    //         }
    //       },
    //     )
    //   )
    // }

    SetItem(item:) -> {
      pure(Model(..model, item:))
    }

    // RecvSubscription(ref:, resp:) -> {
    //   case resp {
    //     api.GotItems(page:) -> todo
    //     api.SubscribedTo(all_subs:) -> todo
    //     api.RespOther -> todo

    //     api.GotItem(item:, action: Created) |
    //     api.GotItem(item:, action: Updated) ->
    //       pure(Model(..model, items: {
    //         model.items |> map_success(dict.insert(_, item.id, item))
    //       }))

    //     api.GotItem(item:, action: Deleted) ->
    //       pure(Model(..model, items: {
    //         model.items |> map_success(dict.delete(_, item.id))
    //       }))
    //   }
    // }

    RecvItem(Error(err)) -> {
      io.println_error("`RecvItem` err: " <> err |> string.inspect)
      pure(model)
    }

    RecvItem(Ok(#(item, Deleted))) -> {
      Model(..model, uuid: uuid.v7(), item: None, items: {
        model.items
        |> map_success(dict.delete(_, item.id))
      })
      |> eff([
        set_focus("item-name"),
      ])
    }

    RecvItem(Ok(#(item, Created))) |
    RecvItem(Ok(#(item, Updated))) -> {
      let items =
        case model.items {
          client.NotAsked | client.Loading | client.Failure(err: _) ->
            client.Success(dict.new())

          client.Success(items) ->
            client.Success(items)
        }
        |> map_success(dict.insert(_, item.id, item))

      Model(..model, uuid: uuid.v7(), item: None, items:)
      |> eff([
        set_focus("item-name"),
      ])
    }

    GotItemForm(values:) -> {
      let assert Ok(name) = values |> list.key_find("name")
      let data = client.Item(name:)

      let req =
        case model.item {
          None ->
            client.req_create_items(
              data:,
              msg: fn(result) {
                result
                |> result.map(pair.new(_, Created))
                |> RecvItem
              },
            )

          Some(item) ->
            client.req_update_items(
              id: item.id,
              data:,
              msg: fn(result) {
                result
                |> result.map(pair.new(_, Updated))
                |> RecvItem
              },
            )
        }

      model.client.send(model, req)
    }

    RecvItems(result:) ->
      case result {
        Ok(generic.Paginated(resources: new, ..)) ->
          pure(Model(..model, items: {
            case model.items {
              client.NotAsked | client.Loading | client.Failure(err: _) -> dict.new()
              client.Success(data: items) -> items
            }
            |> fn(old) {
              new
              |> list.map(fn(item: Record(client.Item)) {
                #(item.id, item)
              })
              |> dict.from_list
              |> dict.merge(old, _)
              |> client.Success
            }
          }))

        Error(err) ->
          pure(Model(..model, items: client.Failure(err)))
      }

    RecvWebSocketEvent(event: ws.OnOpen(conn)) -> {
      io.println("WebSocket opened: " <> ws_url)

      Model(..model, conn: Some(conn))
      |> model.client.send(client.req_list_items(params: None, msg: RecvItems))

      // let #(model, sub_to_items_eff) =
      //   Model(..model, conn: Some(conn), items: Loading)
      //   |> send(
      //     req: api.Subscribe(subs: dict.from_list([#(uuid.v7_string(), api.SubItems)])),
      //     handler: send_msg(
      //       msg: fn(msg) {
      //         io.println("Subscribed: " <> string.inspect(msg))
      //         NoOp
      //       },
      //       map: fn(resp) {
      //         case resp {
      //           api.SubscribedTo(all_subs:) -> Ok(all_subs)
      //           _ -> Error(Nil)
      //         }
      //       },
      //     ),
      //   )

      // model
      // |> eff([
      //   list_items_eff,
      //   sub_to_items_eff,
      // ])
    }

    RecvWebSocketEvent(event: ws.OnClose(reason)) -> {
      io.println_error("WebSocket closed: " <> reason |> string.inspect)
      pure(Model(..model, conn: None))
    }

    RecvWebSocketEvent(event: ws.InvalidUrl) -> {
      io.println_error("Invalid URL: " <> ws_url)
      pure(model)
    }

    RecvWebSocketEvent(event: ws.OnBinaryMessage(ba)) -> {
      io.println_error("Ignoring WebSocket binary msg: " <> ba |> string.inspect)
      pure(Model(..model, conn: None))
    }

    RecvWebSocketEvent(event: ws.OnTextMessage(msg)) -> {
      echo msg

      model.client.recv(model, msg)
    }
  }
}

fn map_success(
  data data: client.ApiData(a),
  apply f: fn(a) -> b,
) -> client.ApiData(b) {
  case data {
    client.NotAsked -> client.NotAsked
    client.Loading -> client.Loading
    client.Failure(err:) -> client.Failure(err:)
    client.Success(data:) -> client.Success(data: f(data))
  }
}

// type RemoteData(t, err) {
//   NotAsked
//   Loading
//   Success(data: t)
//   Failure(err: err)
// }

// fn map_success(
//   data data: RemoteData(a, err),
//   apply f: fn(a) -> b,
// ) -> RemoteData(b, err) {
//   case data {
//     NotAsked -> NotAsked
//     Loading -> Loading
//     Failure(err:) -> Failure(err:)
//     Success(data:) -> Success(data: f(data))
//   }
// }

fn pop(
  reqs reqs: Dict(Uuid, ApiRespHandler),
  resp resp: SocketResp,
) -> #(Dict(Uuid, ApiRespHandler), Result(ApiRespHandler, Nil)) {
  case dict.get(reqs, resp.ref) {
    Ok(handler) ->
      #(dict.delete(reqs, resp.ref), Ok(handler))

    Error(Nil) ->
      #(reqs, Error(Nil))
  }
}

fn process(
  model model: Model,
  resp resp: SocketResp,
  msg msg: fn(String, api.Resp) -> Msg,
) -> #(Model, Effect(Msg)) {
  // let #(reqs, handler) = pop(model.reqs, resp)

  // case resp.ref |> uuid.to_string, resp.result {
  //   "pubsub:" <> _ref, Error(err) -> {
  //     io.println_error("Received pubsub err msg: " <> err |> string.inspect)
  //     pure(model)
  //   }

  //   "pubsub:" <> ref, Ok(resp) -> {
  //     model
  //     |> eff([
  //       effect.from(fn(dispatch) {
  //         dispatch(msg(ref, resp))
  //       }),
  //     ])
  //   }

  //   _ref, _ -> {
  //     let #(model, resp_eff) =
  //       case handler {
  //         Ok(SetRemoteData(set:)) ->
  //           pure(model |> set(resp.result))

  //         Ok(SendMsg(msg:)) ->
  //           model
  //           |> eff([
  //             effect.from(fn(dispatch) {
  //               dispatch(msg(resp.result))
  //             }),
  //           ])

  //         Error(Nil) -> {
  //           // TODO
  //           io.println_error("WebSocket resp ref not found in reqs: " <> resp |> string.inspect)
  //           pure(model)
  //         }
  //       }

  //     Model(..model, reqs:)
  //     |> eff([
  //       resp_eff,
  //     ])
  //   }
  // }
}

// fn handle_websocket_text(
//   model model: Model,
//   msg msg: String,
// ) -> #(Model, Effect(Msg)) {
//   case json.parse(msg, api.decoder_socket_resp()) {
//     Ok(resp) -> {
//       // model |> process(resp:, msg: RecvSubscription)
//       todo as "tk"
//     }

//     Error(err) -> {
//       io.println_error("WebSocket msg json parse failed:")
//       io.println_error(err |> string.inspect)
//       io.println_error(msg)
//       pure(model)
//     }
//   }
// }

fn view(
  model model: Model,
) -> Element(Msg) {
  html.div([], [
    html.div([], [
      html.p([], [
        html.text(string.inspect(model.str)),
      ]),
      html.button([
        event.on_click(Send(num: 123)),
      ], [
        html.text("Send"),
      ]),
    ]),
    view_items(model:),
    view_item_form(model:),
  ])
}

fn view_item_form(
  model model: Model,
) -> Element(Msg) {
  let item_id: String =
    model.item
    |> option.map(fn(item) { item.id.id })
    |> option.unwrap(model.uuid |> uuid.to_string)

  html.div([], [
    keyed.div([], [#(item_id,
      html.form([
        event.on_submit(GotItemForm),
      ], [
        html.p([], [
          html.label([
            attr.for("item-id"),
          ], [
            html.text("Item ID: "),
          ]),
          // html.span([], [html.text(" ")]),
          html.input([
            attr.disabled(True),
            attr.id("item-id"),
            attr.name("id"),
            attr.type_("text"),
            case model.item {
              Some(item) -> attr.value(item.id.id)
              None -> attr.none()
            },
          ]),
        ]),
        html.p([], [
          html.label([
            attr.for("item-name"),
          ], [
            html.text("Item name: "),
          ]),
          // html.span([], [html.text(" ")]),
          html.input([
            attr.id("item-name"),
            attr.name("name"),
            attr.type_("text"),
            case model.item {
              Some(item) -> attr.value(item.resource.name)
              None -> attr.none()
            },
          ]),
        ]),
        html.button([
          attr.type_("submit"),
        ], [
          html.text("Submit"),
        ]),
      ]),
    )
    ]),
    case model.item {
      None ->
        element.none()

      Some(item) ->
        html.div([], [
          html.button([
            event.on_click(SetItem(None)),
          ], [
            html.text("Cancel"),
          ]),
          html.button([
            // event.on_click(DeleteItem(id: item.id)),
          ], [
            html.text("Delete"),
          ]),
        ])
    }
  ])
}

fn view_items(
  model model: Model,
) -> Element(Msg) {
  html.ul([], {
    case model.items {
      client.NotAsked |
      client.Loading |
      client.Failure(err: _) ->
        [html.text(model.items |> string.inspect)]

      client.Success(data: items) ->
        items
        |> dict.to_list
        |> list.map(pair.second)
        |> list.sort(fn(a: Record(client.Item), b: Record(client.Item)) {
          string.compare(a.resource.name, b.resource.name)
        })
        |> list.map(fn(item) {
          html.li([
            event.on_click(SetItem(item: Some(item))),
          ], [
            html.code([], [
              html.text("(" <> item.id.id <> ") "),
            ]),
            html.span([], [
              html.text(item.resource.name),
            ]),
          ])
        })
    }
  })
}


// lustre helpers

fn pure(
  model model: Model,
) -> #(Model, Effect(Msg)) {
  model |> pair.new(effect.none())
}

fn eff(
  model model: Model,
  effs effs: List(Effect(Msg))
) -> #(Model, Effect(Msg)) {
  model |> pair.new(effect.batch(effs))
}

// websockets helpers

fn send(
  model model: Model,
  req req: api.Req,
  handler handler: ApiRespHandler,
) -> #(Model, Effect(Msg)) {
  // case model.conn {
  //   None ->
  //     pure(model)

  //   Some(conn) -> {
  //     let ref = uuid.v7_string()

  //     model
  //     |> listen_for(ref:, handler:)
  //     |> eff([
  //       api.socket_req(ref:, req:)
  //       |> api.encode_socket_req
  //       |> json.to_string
  //       |> ws.send(conn, _)
  //     ])
  //   }
  // }
}

fn listen_for(
  model model: Model,
  ref ref: String,
  handler handler: ApiRespHandler,
) -> Model {
  // Model(..model, reqs: {
  //   model.reqs
  //   |> dict.insert(ref, handler)
  // })
}

// //

// type NewMsg {
//   NewGotItems(items: List(Record(api.Item)))
// }

// type NewSocket {
//   NewSocket(
//     reqs: Reqs,
//     conn: Option(ws.WebSocket),
//   )
// }

// type Reqs = Dict(Uuid, fn(Dynamic) -> Result(NewMsg, RecvErr))

// type NoConn {
//   NoConn
// }

// type NewReq(msg) {
//   NewReq(
//     ref: Uuid,
//     req: api.Req,
//     resp: fn(Dynamic) -> Result(msg, RecvErr)
//   )
// }

// fn pop_req(
//   reqs reqs: Reqs,
//   ref ref: Uuid,
// ) -> Result(#(Reqs, fn(Dynamic) -> Result(NewMsg, RecvErr)), Nil) {
//   reqs
//   |> dict.get(ref)
//   |> result.map(pair.new(dict.delete(reqs, ref), _)) // TODO lazy
// }

// fn build_req(
//   req req: api.Req,
//   decoder decoder: Decoder(t),
//   msg msg: fn(t) -> msg,
// ) -> NewReq(msg) {
//   let ref = uuid.v7()

//   let resp =
//     fn(dyn) {
//       dyn
//       |> decode.run(decoder)
//       |> result.map(msg)
//       |> result.map_error(DecodeErrs(ref:, errs: _))
//     }

//   NewReq(ref:, req:, resp:)
// }

// fn socket_listen(
//   socket socket: NewSocket,
//   req req: NewReq(NewMsg)
// ) -> Result(NewSocket, NoConn) {
//   socket.reqs
//   |> generic_listen(conn: socket.conn, req:)
//   |> result.map(fn(reqs) {
//     NewSocket(..socket, reqs:)
//   })
// }

// fn generic_listen(
//   reqs reqs: Reqs,
//   conn conn: Option(ws.WebSocket),
//   req req: NewReq(NewMsg)
// ) -> Result(Reqs, NoConn) {
//   case conn {
//     None ->
//       Error(NoConn)

//     Some(conn) -> {
//       api.socket_req(ref: req.ref |> uuid.to_string(), req: req.req)
//       |> api.encode_socket_req
//       |> json.to_string
//       |> ws.send(conn, _)

//       Ok(reqs |> dict.insert(req.ref, req.resp))
//     }
//   }
// }

// type ApiErr

// type RecvErr {
//   NoRef(
//     json: String,
//   )
//   UuidParseFailure(
//     ref: String,
//   )
//   ReqNotFound(
//     ref: Uuid,
//     json: String,
//   )
//   RespNotFound(
//     ref: Uuid,
//     json: String,
//   )
//   JsonDecodeErr(
//     ref: Uuid,
//     err: json.DecodeError,
//   )
//   DecodeErrs(
//     ref: Uuid,
//     errs: List(decode.DecodeError),
//   )
// }

// // impl server

// fn exp_api_resp(
//   ref ref: String,
//   req req: api.ExpReq,
// ) -> Result(Json, ApiErr) {
//   case req {
//     api.Items(generic.C(req:)) -> todo
//     api.Items(generic.R(req:)) -> todo
//     api.Items(generic.U(req:)) -> todo
//     api.Items(generic.D(req:)) -> todo
//     api.Items(generic.X(req:)) -> todo

//     api.Items(generic.L(req:)) ->
//       req
//       |> list_items_exp_api_resp // process
//       |> result.map(json_list_items.encode) // encode json
//   }
//   |> result.map(fn(json) {
//     json.object([
//       #("ref", json.string(ref)),
//       #("resp", json),
//     ])
//   })
// }

// // json

// type Transcoders(t) {
//   Transcoders(
//     decoder: fn() -> Decoder(t),
//     encode: fn(t) -> Json,
//   )
// }

// const json_list_items: Transcoders(Paginated(api.Item)) =
//   Transcoders(
//     decoder: decoder_list_items,
//     encode: encode_list_items,
//   )

// // const json_read_item: Transcoders(Record(api.Item)) =
// //   Transcoders(
// //     decoder: decoder_list_items,
// //     encode: encode_list_items,
// //   )

// type Paginated(t) {
//   Paginated(
//     resources: Records(t),
//     pagination: Pagination,
//   )
// }

// fn decoder_list_items() -> Decoder(Paginated(api.Item)) {
//   decoder_paginated(api.decoder_item())
// }

// fn encode_list_items(
//   value value: Paginated(api.Item)
// ) -> Json {
//   encode_paginated(value, api.encode_item)
// }

// fn decoder_paginated(
//   decoder decoder: Decoder(t),
// ) -> Decoder(Records(t)) {
//   decode.list(generic.decoder_record(decoder))
// }

// fn encode_paginated(
//   value value: Paginated(t),
//   encode encode: fn(t) -> Json,
// ) -> Json {
//   json.array(value, generic.encode_record(_, encode))
// }

// // server

// fn list_items_exp_api_resp(
//   req req: generic.ListReq(api.Item),
// ) -> Result(Records(api.Item), ApiErr) {
//   todo
// }

// // client

// type ClientReq(t) {
//   ClientReq(
//     ref: String,
//     req: api.ExpReq,
//     decoder: Decoder(t),
//   )
// }

// fn client_recv(
//   reqs reqs: Reqs,
//   json json: String,
// ) -> Result(#(Reqs, NewMsg), RecvErr) {
//   use ref <- result.try(
//     decode.at(["ref"], decode.string)
//     |> json.parse(json, _)
//     |> result.replace_error(NoRef(json:))
//   )
//   use ref <- result.try(
//     uuid.from_string(ref)
//     |> result.replace_error(UuidParseFailure(ref:))
//   )
//   use resp <- result.try(
//     decode.at(["resp"], decode.dynamic)
//     |> json.parse(json, _)
//     |> result.replace_error(RespNotFound(ref:, json:))
//   )
//   use #(reqs, to_msg) <- result.try(
//     pop_req(reqs, ref)
//     |> result.replace_error(ReqNotFound(ref:, json:))
//   )

//   use msg <- result.try(resp |> to_msg)

//   Ok(#(reqs, msg))
// }

// fn list_items_exp_api_req(
//   pagination pagination: Option(Pagination),
// ) -> fn(String) -> ClientReq(Records(api.Item)) {
//   ClientReq(
//     ref: _,
//     req: api.Items(generic.L(generic.ListReq(pagination:))),
//     decoder: json_list_items.decoder(),
//   )
// }

// fn decoder_exp_api_resp(
//   decoder decoder: Decoder(t),
// ) -> Decoder(#(String, t)) {
//   use ref <- decode.field("ref", decode.string)
//   use resp <- decode.field("resp", decoder)

//   decode.success(#(ref, resp))
// }
