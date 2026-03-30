import gleam/dict.{type Dict}
import gleam/string
import gleam/io
import gleam/option.{type Option, Some, None}
import gleam/json
import lustre/component
import lustre/element.{type Element}
import lustre/element/html
import gleam/pair
import lustre/effect.{type Effect}
import lustre
import lustre_websocket.{type WebSocketEvent} as ws
import api.{type SocketResp}
import api/generic.{List, type Record, type Records}
import youid/uuid

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
    items: RemoteData(List(Record(api.Item)), api.Err),
    //
    reqs: Dict(String, ApiRespHandler),
  )
}

type ApiRespHandler {
  SetRemoteData(set: fn(Model, Result(api.Resp, api.Err)) -> Model)
  SendMsg(msg: fn(Result(api.Resp, api.Err)) -> Msg)
}

type Msg {
  NoOp
  GotWebSocketEvent(event: WebSocketEvent)
  RecvItems(result: Result(Records(api.Item), api.Err))
}

fn init(_) -> #(Model, Effect(Msg)) {
  Model(
    conn: None,
    items: NotAsked,
    //
    reqs: dict.new(),
  )
  |> pair.new(effect.batch([
    ws.init(ws_url, GotWebSocketEvent),
  ]))
}

const ws_url = "/ws/api"

fn set_remote_data(
  map map: fn(api.Resp) -> Result(t, Nil),
  set set: fn(Model, RemoteData(t, api.Err)) -> Model,
) -> ApiRespHandler {
  SetRemoteData(set: fn(model, result) {
    case result {
      Error(err) -> {
        model |> set(Failure(err:))
      }

      Ok(resp) ->
        case map(resp) {
          Ok(data) ->
            model |> set(Success(data:))

          Error(Nil) -> {
            io.println_error("Failed to map api result: " <> result |> string.inspect)
            model
          }
        }
    }
  })
}

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
            NoOp
          }
        }
    }
  })
}

fn update(
  model model: Model,
  msg msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    NoOp ->
      pure(model)

    RecvItems(result:) ->
      case result {
        Ok(items) ->
          pure(Model(..model, items: Success(items)))

        Error(err) ->
          pure(Model(..model, items: Failure(err)))
      }

    GotWebSocketEvent(event: ws.OnOpen(conn)) -> {
      io.println("WebSocket opened: " <> ws_url)
      Model(..model, conn: Some(conn), items: Loading)
      |> send(
        req: api.CrudItems(List(None)),
        handler: send_msg(
          msg: RecvItems,
          map: fn(resp) {
            case resp {
              api.GotItems(page:) -> Ok(page.resources)
              _ -> Error(Nil)
            }
          },
        ),
        // handler: set_remote_data(
        //   set: fn(model, items) { Model(..model, items:) },
        //   map: fn(resp) {
        //     case resp {
        //       api.GotItems(page:) -> Ok(page.resources)
        //       _ -> Error(Nil)
        //     }
        //   },
        // ),
      )
    }

    GotWebSocketEvent(event: ws.OnClose(reason)) -> {
      io.println_error("WebSocket closed: " <> reason |> string.inspect)
      pure(Model(..model, conn: None))
    }

    GotWebSocketEvent(event: ws.InvalidUrl) -> {
      io.println_error("Invalid URL: " <> ws_url)
      pure(model)
    }

    GotWebSocketEvent(event: ws.OnBinaryMessage(ba)) -> {
      io.println_error("Ignoring WebSocket binary msg: " <> ba |> string.inspect)
      pure(Model(..model, conn: None))
    }

    GotWebSocketEvent(event: ws.OnTextMessage(msg)) ->
      handle_websocket_text(model:, msg:)
  }
}

type RemoteData(t, err) {
  NotAsked
  Loading
  Success(data: t)
  Failure(err: err)
}

fn pop(
  reqs reqs: Dict(String, ApiRespHandler),
  resp resp: SocketResp,
) -> #(Dict(String, ApiRespHandler), Result(ApiRespHandler, Nil)) {
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
) -> #(Model, Effect(Msg)) {
  let #(reqs, handler) = pop(model.reqs, resp)

  let #(model, resp_eff) =
    case handler {
      Ok(SetRemoteData(set:)) ->
        pure(model |> set(resp.result))

      Ok(SendMsg(msg:)) ->
        model
        |> eff([
          effect.from(fn(dispatch) {
            dispatch(msg(resp.result))
          }),
        ])

      Error(Nil) -> {
        // TODO
        io.println_error("WebSocket resp ref not found in reqs: " <> resp |> string.inspect)
        pure(model)
      }
    }

  Model(..model, reqs:)
  |> eff([
    resp_eff,
  ])
}

fn handle_websocket_text(
  model model: Model,
  msg msg: String,
) -> #(Model, Effect(Msg)) {
  case json.parse(msg, api.decoder_socket_resp()) {
    Ok(resp) -> {
      model |> process(resp:)
    }

    Error(err) -> {
      io.println_error("WebSocket msg json parse failed:")
      io.println_error(err |> string.inspect)
      io.println_error(msg)
      pure(model)
    }
  }
}

fn view(
  model model: Model,
) -> Element(Msg) {
  html.div([], [
    html.text(model.items |> string.inspect)
  ])
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
  case model.conn {
    None ->
      pure(model)

    Some(conn) -> {
      let ref = uuid.v7_string()

      model
      |> listen_for(ref:, handler:)
      |> eff([
        api.socket_req(ref:, req:)
        |> api.encode_socket_req
        |> json.to_string
        |> ws.send(conn, _)
      ])
    }
  }
}

fn listen_for(
  model model: Model,
  ref ref: String,
  handler handler: ApiRespHandler,
) -> Model {
  Model(..model, reqs: {
    model.reqs
    |> dict.insert(ref, handler)
  })
}
