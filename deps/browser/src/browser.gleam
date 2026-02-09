import gleam/result.{try}
import gleam/list
import gleam/javascript/array
import plinth/browser/document
import plinth/browser/element

pub fn main() -> Nil {
  put_user_client_info_if_not_set()
}

fn put_user_client_info_if_not_set() -> Nil {
  {
    use meta <- try(
      document.query_selector_all("meta")
      |> array.to_list
      |> list.find(fn(meta) {
        let name = meta |> element.get_attribute("name")
        name == Ok("no-user-client-info")
      })
    )

    use path_prefix <- try(
      element.dataset_get(meta, "path_prefix")
    )

    Ok(put_user_client_info(path_prefix:))
  }
  |> result.unwrap(Nil)
}

@external(javascript, "./browser_ffi.mjs", "put_user_client_info")
fn put_user_client_info(path_prefix path_prefix: String) -> Nil
