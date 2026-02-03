import gleam/option.{type Option, Some, None}
import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import app/types.{type Context}
import wisp

pub fn handler(
  req req: Request(wisp.Connection),
  ctx _ctx: Context(config, user),
) -> Response(wisp.Body) {
  case req |> wisp.path_segments {
    [] ->
      "hi"
      |> wisp.html_response(200)

    // TODO mv out to a generic router
    ["internal-server-error"] -> wisp.internal_server_error()
    ["unprocessable_entity"] -> wisp.unprocessable_content()
    ["method-not-allowed"] -> wisp.method_not_allowed([])
    ["entity-too-large"] -> wisp.content_too_large()
    ["bad-request"] -> wisp.bad_request("") // TODO
    _ -> wisp.not_found()
  }
}
