import gleam/erlang/process
import gleam/http/response
import gleam/http/request
import gleam/bytes_tree
import mist

pub fn main() -> Nil {
  let assert Ok(_) =
    app
    |> mist.new()
    // |> mist.bind("0.0.0.0")
    // |> mist.with_ipv6
    |> mist.bind("localhost")
    |> mist.port(5000)
    |> mist.start

  process.sleep_forever()
}

fn app(
  req: request.Request(mist.Connection),
) -> response.Response(mist.ResponseData) {
  case req |> request.path_segments {
    [] ->
      200
      |> response.new
      |> response.set_body({
        "hi"
        |> bytes_tree.from_string
        |> mist.Bytes
      })

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
