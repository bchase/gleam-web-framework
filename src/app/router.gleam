import gleam/option.{type Option, Some, None}
import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import app/types.{type Context}
import wisp

pub fn handler(
  req req: Request(wisp.Connection),
  ctx ctx: Context(user),
) -> Response(wisp.Body) {
  case req |> wisp.path_segments {
    _ ->
      ""
      |> wisp.html_response(200)
  }
}
