import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, Some}
import app/types.{type Context}
import lustre
import lustre/runtime/server/runtime
import lustre/server_component
import mist

pub fn start(
  req req: Request(mist.Connection),
  ctx ctx: Context(config, user),
  app app: lustre.App(Context(config, user), model, msg),
  // build_selectors build_selectors: Option(App(List(Selector(msg)), config, user)),
) -> Response(mist.ResponseData) {
  mist.websocket(
    request: req,
    // on_init: init(ws_conn: _, app:, ctx:, build_selectors:),
    on_init: init(ws_conn: _, app:, ctx:),
    handler: update,
    on_close: close,
  )
}

type Socket(msg) {
  Socket(
    component: lustre.Runtime(msg),
    self: Subject(server_component.ClientMessage(msg)),
  )
}

type SocketMsg(msg) {
  LustreMsg(msg: server_component.ClientMessage(msg))
  AppMsg(msg: msg)
}

type SocketInit(msg) =
  #(Socket(msg), Option(Selector(SocketMsg(msg))))

fn init(
  ws_conn _ws_conn,
  app app: lustre.App(Context(config, user), model, msg),
  ctx ctx: Context(config, user),
  // build_selectors: Option(App(List(Selector(msg)), config, user)),
) -> SocketInit(msg) {
  let assert Ok(component) = lustre.start_server_component(app, ctx)

  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select_map(self, LustreMsg)
    // |> fn(selector) {
    //   case build_selectors {
    //     None ->
    //       selector

    //     Some(build_selectors) ->
    //       case app.run(build_selectors, ctx) {
    //         Error(err) -> {
    //           err
    //           |> string.inspect
    //           |> io.println_error

    //           panic // TODO
    //         }

    //         Ok(sels) ->
    //           sels
    //           |> list.fold(selector, fn(selector, sel) {
    //             selector
    //             |> process.merge_selector(sel |> process.map_selector(AppMsg))
    //           })
    //       }
    //   }
    // }

  server_component.register_subject(self)
  |> lustre.send(to: component)

  #(Socket(component:, self:), Some(selector))
}

fn update(
  socket: Socket(msg),
  msg: mist.WebsocketMessage(SocketMsg(msg)),
  conn: mist.WebsocketConnection,
) {
  case msg {
    mist.Text(json) -> {
      case json.parse(json, server_component.runtime_message_decoder()) {
        Ok(runtime_msg) -> lustre.send(socket.component, runtime_msg)
        Error(_) -> Nil
      }

      mist.continue(socket)
    }

    mist.Binary(_) -> mist.continue(socket)

    mist.Custom(msg) -> {
      case msg {
        LustreMsg(msg:) -> {
          let json = server_component.client_message_to_json(msg)
          let assert Ok(_) = mist.send_text_frame(conn, json.to_string(json))

          mist.continue(socket)
        }

        AppMsg(msg:) -> {
          lustre.send(
            message: msg |> runtime.EffectDispatchedMessage,
            to: socket.component,
          )

          mist.continue(socket)
        }
      }
    }

    mist.Closed | mist.Shutdown -> {
      close(socket)

      mist.stop()
    }
  }
}

fn close(socket: Socket(msg)) {
  lustre.shutdown()
  |> lustre.send(to: socket.component)
}
