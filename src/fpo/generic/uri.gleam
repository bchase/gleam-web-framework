import gleam/string
import gleam/uri.{type Uri, Uri}
import gleam/option.{Some, None}

pub fn from(
  path path_segments: List(String),
  params params: List(#(String, String)),
) -> Uri {
  let path =
    path_segments
    |> string.join("/")
    |> string.append(to: "/", suffix: _)

  let query=
    case params {
      [] ->
        None

      _ ->
        params
        |> uri.query_to_string
        |> Some
    }

  Uri(
    scheme: None,
    userinfo: None,
    host: None,
    port: None,
    fragment: None,
    path:,
    query:,
  )
}
