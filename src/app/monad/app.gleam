import gleam/option.{type Option}
import app/types.{type Context}
import app/types/err.{type Err}

pub opaque type App(t, config, user) {
  App(run: fn(Context(config, user)) -> Result(t, Err))
}

pub fn run(
  app app: App(t, config, user),
  read read: Context(config, user),
) -> Result(t, Err) {
  app.run(read)
}

pub fn pure(
  val val: t,
) -> App(t, config, user) {
  App(run: fn(_read) { Ok(val) })
}

pub fn fail(
  err err: Err,
) -> App(t, config, user) {
  App(run: fn(_read) { Error(err) })
}

pub fn map(
  app app: App(a, config, user),
  f f: fn(a) -> b,
) -> App(b, config, user) {
  App(run: fn(read) {
    case app.run(read) {
      Error(err) -> Error(err)
      Ok(x) -> Ok(f(x))
    }
  })
}

pub fn flatten(
  app app: App(App(t, config, user), config, user),
) -> App(t, config, user) {
  App(run: fn(read) {
    case app.run(read) {
      Error(err) -> Error(err)
      Ok(app) -> app.run(read)
    }
  })
}

pub fn do(
  app app: App(a, config, user),
  cont cont: fn(a) -> App(b, config, user),
) -> App(b, config, user) {
  // app |> map(cont) |> flatten
  App(run: fn(read) {
    case app.run(read) {
      Error(err) -> Error(err)
      Ok(x) -> cont(x) |> run(read)
    }
  })
}

pub fn ok(
  result result: Result(t, Err),
) -> App(t, config, user) {
  App(run: fn(_read) { result })
}

pub fn some(
  option option: Option(t),
  err err: Err,
) -> App(t, config, user) {
  App(run: fn(_read) {
    option
    |> option.to_result(err)
  })
}

//


