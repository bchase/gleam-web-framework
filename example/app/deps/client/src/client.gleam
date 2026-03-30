import gleam/dict.{type Dict}
import gleam/bit_array
import gleam/string
import gleam/io
import gleam/option.{type Option, Some, None}
import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}
import lustre/component
import lustre/element.{type Element}
import lustre/element/html
import gleam/pair
import lustre/effect.{type Effect}
import lustre
import lustre_websocket.{type WebSocketEvent} as ws
import api.{type SocketResp}
import api/generic.{List}
import youid/uuid.{type Uuid}

fn send(
  model model: Model,
  req req: api.Req,
  map map: fn(api.Resp) -> Result(t, Nil),
  set set: fn(Model, RemoteData(t, api.Err)) -> Model,
) -> #(Model, Effect(Msg)) {
  case model.conn {
    None ->
      pure(model)

    Some(conn) -> {
      let ref = uuid.v7_string()

      model
      |> listen_for(ref:, map:, set:)
      |> eff([
        api.socket_req(ref:, req:)
        |> api.encode_socket_req
        |> json.to_string
        |> ws.send(conn, _)
      ])
    }
  }
}

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
    items: RemoteData(List(generic.Record(api.Item)), api.Err),
    reqs: Dict(String, fn(Model, Result(api.Resp, api.Err)) -> Model),
  )
}

type Msg {
  NoOp
  GotWebSocketEvent(event: WebSocketEvent)
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

fn update(
  model model: Model,
  msg msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg |> echo {
    NoOp ->
      pure(model)

    GotWebSocketEvent(event: ws.OnOpen(conn)) -> {
      echo "WebSocket opened"
      Model(..model, conn: Some(conn), items: Loading)
      |> send(
        req: api.CrudItems(List(None)),
        map: fn(resp) {
          case resp {
            api.RespItems(resp: generic.GotMany(items)) -> Ok(items)
            _ -> Error(Nil)
          }
        },
        set: fn(model, items) { Model(..model, items:) },
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
  Success(t)
  Failure(err)
}

// fn req(
//   req req: api.Req,
//   msg msg: fn(api.Resp) -> msg,
//   get get: fn(state) -> RemoteData(t, err),
//   set set: fn(state, Result(t, err)) -> state,
// ) -> Effect(msg) {
// }

fn listen_for(
  model model: Model,
  ref ref: String,
  map map: fn(api.Resp) -> Result(t, Nil),
  set set: fn(Model, RemoteData(t, api.Err)) -> Model,
) -> Model {
  Model(..model, reqs: {
    model.reqs
    |> dict.insert(ref, fn(model, result) {
      case result {
        Ok(resp) ->
          case map(resp) {
            Ok(data) ->
              set(model, Success(data))

            Error(Nil) -> {
              // TODO
              io.println_error("failed to map resp to resource")
              model
            }
          }

        Error(err) ->
          set(model, Failure(err))
      }
    })
  })
}

fn process(
  model model: Model,
  resp resp: SocketResp,
) -> Model {
  case dict.get(model.reqs, resp.ref) {
    Ok(set) ->
      set(model, resp.result)

    Error(Nil) -> {
      // TODO
      io.println_error("WebSocket resp ref not found in reqs: " <> resp |> string.inspect)
      model
    }
  }
}

// fn handle_resp(
//   pending pending: fn(state) -> Dict(String, fn(api.Resp) -> state),
// ) {
// }

fn handle_websocket_text(
  model model: Model,
  msg msg: String,
) -> #(Model, Effect(Msg)) {
  echo "WebSocket msg: " <> msg
  case json.parse(msg, api.decoder_socket_resp()) {
    Ok(resp) -> {
      pure(model |> process(resp:))
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

//

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
