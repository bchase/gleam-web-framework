import gleam/list
import gleam/regexp
import gleam/string

pub fn snake(
  str str: String,
) -> String {
  let assert Ok(capital_re) = regexp.from_string("[A-Z]")
  let assert Ok(initial_underscore_re) = regexp.from_string("^[_]")

  str
  |> regexp.match_map(each: capital_re, in: _, with: fn(match) {
    match.content
    |> string.lowercase
    |> string.append(to: "_", suffix: _)
  })
  |> regexp.replace(each: initial_underscore_re, in: _, with: "")
}

pub fn snake_hyphenate(
  str str: String,
) -> String {
  str
  |> snake
  |> string.replace(each: "_", with: "-")
}

pub fn pascal(
  str str: String,
) -> String {
  str
  |> string.split("_")
  |> list.map(string.capitalise)
  |> string.join("")
}
