import gleam/option.{type Option, Some, None}

// FUNCTIONS

pub fn identity(
  val val: t,
) -> t {
  val
}

pub fn always(
  val val: t,
) -> fn(ignored) -> t {
  fn(_) { val }
}

pub fn always_(
  f f: fn( ) -> t,
) -> fn(ignored) -> t {
  fn(_) { f() }
}

// `Result` & `Option`

pub fn option_result_to_result_option(
  option option: Option(Result(t, err)),
) -> Result(Option(t), err) {
  case option {
    None -> Ok(None)
    Some(Ok(x)) -> Ok(Some(x))
    Some(Error(err)) -> Error(err)
  }
}

pub fn result_option_to_option_result(
  result result: Result(Option(t), err),
) -> Option(Result(t, err)) {
  case result {
    Ok(Some(x)) -> Some(Ok(x))
    Ok(None) -> None
    Error(err) -> Some(Error(err))
  }
}
