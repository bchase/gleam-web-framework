import app/types.{type Context}
import app/types/spec.{type Handler}
import gleam/http/request.{type Request}
import gleam/http/response as resp
import mist

pub fn router(
  req req: Request(mist.Connection),
  ctx _ctx: Context(config, user),
) -> Result(resp.Response(mist.ResponseData), Nil) {
  case req |> request.path_segments {
    _ ->
      Error(Nil)
  }
}
