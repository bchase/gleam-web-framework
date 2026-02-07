import gleam/bool
import gleam/list
import gleam/javascript/array
import plinth/browser/document
import plinth/browser/element

pub fn main() -> Nil {
  put_user_client_info_if_not_set()
}

fn put_user_client_info_if_not_set() -> Nil {
  let missing_user_client_info =
    document.query_selector_all("meta")
    |> array.to_list
    |> list.any(fn(meta) {
      let name = meta |> element.get_attribute("name")
      name == Ok("no-user-client-info")
    })

  echo missing_user_client_info

  use <- bool.guard(!missing_user_client_info, Nil)
  echo "SETTING"

  put_user_client_info()
  |> echo

  echo "SET"

  Nil
}

@external(javascript, "./browser_ffi.mjs", "put_user_client_info")
fn put_user_client_info() -> Nil
