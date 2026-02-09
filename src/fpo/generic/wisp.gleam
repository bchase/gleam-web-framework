import gleam/http/response.{type Response}
import gleam/list
import gleam/string
import gleam/uri
import gleam/bit_array
import gleam/http
import gleam/http/request.{type Request}
import gleam/result.{try}
import wisp
import formal/form
import lustre/attribute as attr

pub fn redirect(
  to location: String,
) -> Response(wisp.Body) {
  wisp.response(302)
  |> wisp.set_header("location", location)
}

pub fn action(
  method method: http.Method,
  path path: String,
) -> List(attr.Attribute(msg)) {
  let #(path, query_str) =
    case path |> string.split("?") {
      [] -> #(path, "")
      [path] -> #(path, "")
      [path, query_str, ..] -> #(path, query_str)
    }

  let method =
    method
    |> string.inspect
    |> string.uppercase

  let params =
    case uri.parse_query(query_str) {
      Error(Nil) ->
        [#("_method", method)]

      Ok(params) ->
        params
        |> list.filter(fn(t) {
          let #(key, _val) = t
          key != "_method"
        })
        |> list.append([#("_method", method)])
    }

  let query_str = uri.query_to_string(params)

  let action = path <> "?" <> query_str

  [
    attr.method("POST"),
    attr.action(action),
  ]
}

pub fn read_form_url_encoded(
  req req: Request(wisp.Connection),
) -> Result(List(#(String, String)), Nil) {
  use bytes <- try(wisp.read_body_bits(req))
  use txt <- try(bit_array.to_string(bytes))
  use values <- try(uri.parse_query(txt))
  Ok(values)
}

pub fn read_form(
  req req: Request(wisp.Connection),
  form form: form.Form(form),
) -> Result(form, form.Form(form)) {
  use values <- try(
    read_form_url_encoded(req) |> result.replace_error(form)
  )

  form
  |> form.add_values(values)
  |> form.run
}
