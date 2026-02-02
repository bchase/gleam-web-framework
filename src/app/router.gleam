import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import app/types.{type Config}
import wisp

pub fn handler(
  req req: Request(wisp.Connection),
  cfg _cfg: Config,
) -> Response(wisp.Body) {
  case req |> wisp.path_segments {
    _ ->
      ""
      |> wisp.html_response(200)
  }
}
