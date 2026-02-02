import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import app/types.{type ContextWith}
import wisp

pub fn handler(
  req req: Request(wisp.Connection),
  build_context build_context: fn(Request(wisp.Connection)) -> ContextWith(user),
) -> Response(wisp.Body) {
  let _ctx = build_context(req)

  case req |> wisp.path_segments {
    _ ->
      ""
      |> wisp.html_response(200)
  }
}
