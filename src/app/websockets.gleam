import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import gleam/bytes_tree
import mist.{type Connection, type ResponseData}
import app/types.{type Context}

pub fn handler(
  req req: Request(Connection),
  build_context build_context: fn(Request(mist.Connection)) -> Context(user),
) -> Response(ResponseData) {
  let _ctx = build_context(req)

  case req |> request.path_segments {
    _ ->
      404
      |> response.new
      |> response.set_body({
        "not found"
        |> bytes_tree.from_string
        |> mist.Bytes
      })
  }
}
