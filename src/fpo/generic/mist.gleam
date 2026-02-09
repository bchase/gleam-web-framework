import gleam/bytes_tree
import gleam/http/response.{type Response}
import mist

pub fn empty_resp(
  status status: Int,
) -> Response(mist.ResponseData) {
  status
  |> response.new
  |> response.set_body(
    bytes_tree.new()
    |> mist.Bytes
  )
}

