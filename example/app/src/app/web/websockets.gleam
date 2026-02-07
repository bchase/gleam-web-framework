import fpo/types.{type Context}
import gleam/http/request.{type Request}
import gleam/http/response as resp
import mist
import fpo/lustre/server_component/socket
import app/web/components/counter
import app/web/components/counter_app
import app/web/components/pubsub_demo
import app/web/components/sqlite_demo
import app/web/components/postgres_demo
import app/config

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

    ["ws", "postgres_demo"] ->
      Ok(socket.start(req:, ctx:, app: postgres_demo.component(ctx:)))

    _ ->
      Error(Nil)
  }
}
