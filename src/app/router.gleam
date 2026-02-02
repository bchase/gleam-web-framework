import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import app/types.{type Context}
import wisp

pub fn handler(
  req req: Request(wisp.Connection),
  build_context build_context: fn(Request(wisp.Connection)) -> Context(user),
) -> Response(wisp.Body) {
  let _ctx = build_context(req)

  case req |> wisp.path_segments {
    _ ->
      ""
      |> wisp.html_response(200)
  }
}

pub fn handle_unauthenciated(
  req req: Request(wisp.Connection),
  build_context build_context: fn(Request(wisp.Connection)) -> Context(user),
) -> Response(wisp.Body) {
  let _ctx = build_context(req)

  case req |> wisp.path_segments {
    _ ->
      ""
      |> wisp.html_response(200)
  }
}
