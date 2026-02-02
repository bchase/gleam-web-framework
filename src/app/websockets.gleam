import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import gleam/bytes_tree
import mist.{type Connection, type ResponseData}
import app/types.{type Config}

pub fn handler(
  req req: Request(Connection),
  cfg _cfg: Config,
) -> Response(ResponseData) {
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
