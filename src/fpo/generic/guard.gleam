import gleam/option.{type Option, Some, None}

pub fn some(
  option option: Option(a),
  none val,
  some cont: fn(a) -> b
) -> b {
  case option {
    Some(x) -> cont(x)
    None -> val
  }
}

pub fn some_(
  option option: Option(a),
  none none: fn() -> b,
  some cont: fn(a) -> b
) -> b {
  case option {
    Some(x) -> cont(x)
    None -> none()
  }
}

pub fn ok(
  result result: Result(a, err),
  err val: b,
  ok cont: fn(a) -> b
) -> b {
  case result {
    Ok(x) -> cont(x)
    Error(_err) -> val
  }
}

pub fn ok_(
  result result: Result(a, err),
  err map_err: fn(err) -> b,
  ok cont: fn(a) -> b
) -> b {
  case result {
    Ok(x) -> cont(x)
    Error(err) -> map_err(err)
  }
}
