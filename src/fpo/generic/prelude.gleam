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
