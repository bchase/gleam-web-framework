import app/types.{type Context}
import gleam/http/request.{type Request}
import gleam/http/response as resp
import mist
import app/lustre/server_component/socket
import app/examples/counter

pub fn lustre_server_component_router(
  req req: Request(mist.Connection),
  ctx ctx: Context(config, user),
) -> Result(resp.Response(mist.ResponseData), Nil) {
  case req |> request.path_segments {
    ["ws", "counter"] ->
      Ok(socket.start(req:, ctx:, app: counter.component()))

    _ ->
      Error(Nil)
  }
}
