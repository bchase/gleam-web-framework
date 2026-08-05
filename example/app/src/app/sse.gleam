import gleam/bytes_tree
import fpo/types
import fpo/monad/app
import bchase/web/sse.{type SSE} as _
import bchase/erl/sse as erl_sse
import fpo/types/err
import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import mist
import fpo/pubsub.{type PubSub} as _

pub fn subscribe(
  sse sse: SSE(broadcast),
  to channel: String,
  in pubsub: fn(pubsub) -> PubSub(listen),
  wrap to_msg: fn(listen) -> broadcast,
) -> #(List(String), fn(Request(mist.Connection), types.Context(config, pubsub, user)) -> Response(mist.ResponseData)) {
  erl_sse.serve_via_mist(sse:, listen: fn(_req, ctx) {
    app.subscribe(
      to: channel,
      in: pubsub,
      wrap: to_msg,
    )
    |> app.run(ctx, Nil)
  })
}

pub fn err_empty_500(
  _err: err.Err(mist.Connection),
  _req: Request(req),
  _ctx: ctx,
) -> Response(mist.ResponseData) {
  response.new(500)
  |> response.set_body(mist.Bytes(bytes_tree.new()))
}
