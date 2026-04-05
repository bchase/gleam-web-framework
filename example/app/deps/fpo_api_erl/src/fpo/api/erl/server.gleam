import api/types.{SocketReq, type SocketResp,}
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/json
import gleam/option.{type Option, Some, None}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import mist
import youid/uuid

pub type Server(req, context) {
  Server(
    call: fn(types.SocketReq(req), context, Set(String), fn(SocketResp) -> Msg) -> #(Set(String), SocketResp, Option(Selector(Msg))),
    decoder: Decoder(req),
  )
}

//

pub opaque type Socket(context) {
  Socket(
    self: Subject(Msg),
    subs: Set(String),
  )
}

pub opaque type Msg {
  NoOp
  Broadcast(msg: SocketResp)
}

pub fn start(
  req req: Request(mist.Connection),
  ctx ctx: context,
  server server: Server(api, context)
) -> Response(mist.ResponseData) {
  mist.websocket(
    request: req,
    on_init: init,
    handler: fn(socket, msg, conn) {
      update(socket:, msg:, conn:, server:, ctx:)
    },
    on_close: close,
  )
}

fn init(
  _conn: mist.WebsocketConnection,
) -> #(Socket(context), Option(Selector(Msg))) {
  let self = process.new_subject()

  #(Socket(self:, subs: set.new()), Some(
    process.new_selector()
    |> process.select(self)
  ))
}

fn update(
  socket socket: Socket(context),
  msg msg: mist.WebsocketMessage(Msg),
  conn conn: mist.WebsocketConnection,
  server server: Server(api, context),
  ctx ctx: context,
) -> mist.Next(Socket(context), Msg) {
  case msg {
    mist.Custom(msg) ->
      update_custom(socket:, msg:, conn:)

    mist.Text(msg) ->
      respond_using(server:, socket:, msg:, conn:, ctx:)

    mist.Binary(msg) ->
      ignore_binary_msg_with_warning(socket:, msg:)

    mist.Closed | mist.Shutdown ->
      stop_after_running_closed_callback(socket:, close:)
  }
}

fn update_custom(
  socket socket: Socket(context),
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
  socket socket: Socket(context),
  msg msg: BitArray,
) -> mist.Next(Socket(context), Msg) {
  io.println_error("[WARNING] websocket ignoring binary msg: " <> string.inspect(msg))
  mist.continue(socket)
}

fn respond_using(
  server server: Server(req, context),
  socket socket: Socket(context),
  msg msg: String,
  conn conn: mist.WebsocketConnection,
  ctx ctx: context,
) -> mist.Next(Socket(context), Msg) {
  case parse_socket_req(msg, server.decoder) {
    Ok(req) -> {
      let #(subs, resp, selector) = server.call(req, ctx, socket.subs, Broadcast)

      let selector =
        {
          use selector <- option.map(selector)
          selector
          |> process.select(socket.self)
        }

      resp
      |> types.encode_socket_resp
      |> json.to_string
      |> send(conn)

      let socket =
        Socket(..socket, subs: subs)

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

fn stop_after_running_closed_callback(
  socket socket: Socket(context),
  close close: fn(Socket(context)) -> Nil,
) -> mist.Next(Socket(context), Msg) {
  close(socket)
  mist.stop()
}

fn close(
  socket _socket: Socket(context),
) -> Nil {
  Nil
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
