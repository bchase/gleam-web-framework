import app/types.{type Context}
import gleam/http/request.{type Request}
import gleam/http/response as resp
import mist
import app/lustre/server_component/socket
import app/examples/counter
import app/examples/counter_app
import app/examples/pubsub_demo
import app/examples/sqlite_demo
import spec/config

pub fn lustre_server_component_router(
  req req: Request(mist.Connection),
  ctx ctx: Context(config.Config, config.PubSub, user),
) -> Result(resp.Response(mist.ResponseData), Nil) {
  case req |> request.path_segments {
    ["ws", "counter"] ->
      Ok(socket.start(req:, ctx:, app: counter.component()))

    ["ws", "counter_app"] ->
      Ok(socket.start(req:, ctx:, app: counter_app.component(ctx:)))

    ["ws", "pubsub_demo"] ->
      Ok(socket.start(req:, ctx:, app: pubsub_demo.component(ctx:)))

    ["ws", "sqlite_demo"] ->
      Ok(socket.start(req:, ctx:, app: sqlite_demo.component(ctx:)))

    _ ->
      Error(Nil)
  }
}
