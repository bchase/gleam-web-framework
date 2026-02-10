import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, Some, None}
import fpo/types.{type Context}
import fpo/types/err.{type Err}
import fpo/pubsub
import fpo/generic/guard

pub opaque type App(t, config, pubsub, user) {
  App(run: fn(Context(config, pubsub, user)) -> Result(t, Err))
}

pub fn run(
  app app: App(t, config, pubsub, user),
  read read: Context(config, pubsub, user),
) -> Result(t, Err) {
  app.run(read)
}

pub fn pure(
  val val: t,
) -> App(t, config, pubsub, user) {
  App(run: fn(_read) { Ok(val) })
}

pub fn fail(
  err err: Err,
) -> App(t, config, pubsub, user) {
  App(run: fn(_read) { Error(err) })
}

pub fn ctx() -> App(Context(config, pubsub, user), config, pubsub, user) {
  App(run: fn(read) { Ok(read) })
}

pub fn map(
  app app: App(a, config, pubsub, user),
  f f: fn(a) -> b,
) -> App(b, config, pubsub, user) {
  App(run: fn(read) {
    case app.run(read) {
      Error(err) -> Error(err)
      Ok(x) -> Ok(f(x))
    }
  })
}

pub fn flatten(
  app app: App(App(t, config, pubsub, user), config, pubsub, user),
) -> App(t, config, pubsub, user) {
  App(run: fn(read) {
    case app.run(read) {
      Error(err) -> Error(err)
      Ok(app) -> app.run(read)
    }
  })
}

pub fn do(
  app app: App(a, config, pubsub, user),
  cont cont: fn(a) -> App(b, config, pubsub, user),
) -> App(b, config, pubsub, user) {
  // app |> map(cont) |> flatten
  App(run: fn(read) {
    case app.run(read) {
      Error(err) -> Error(err)
      Ok(x) -> cont(x) |> run(read)
    }
  })
}

pub fn do_(
  app app: App(Result(a, e1), config, pubsub, user),
  fail fail: fn(e1) -> e2,
  cont cont: fn(a) -> App(Result(b, e2), config, pubsub, user),
) -> App(Result(b, e2), config, pubsub, user) {
  use result <- do(app)

  case result {
    Ok(x) -> cont(x)
    Error(err) -> pure(Error(fail(err)))
  }
}

pub fn do__(
  app app: App(Result(a, e1), config, pubsub, user),
  fail err: e2,
  cont cont: fn(a) -> App(Result(b, e2), config, pubsub, user),
) -> App(Result(b, e2), config, pubsub, user) {
  do_(app:, fail: fn(_) { err }, cont:)
}

pub fn ok(
  result result: Result(t, Err),
) -> App(t, config, pubsub, user) {
  App(run: fn(_read) { result })
}

pub fn some(
  option option: Option(t),
  err err: Err,
) -> App(t, config, pubsub, user) {
  App(run: fn(_read) {
    option
    |> option.to_result(err)
  })
}

pub fn sequence(
  apps apps: List(App(a, config, pubsub, user)),
) -> App(List(a), config, pubsub, user) {
  App(fn(r) {
    apps
    |> list.fold_until(Ok([]), fn(acc, app) {
      case acc {
        Error(err) ->
          list.Stop(Error(err))

        Ok(acc) ->
          case run(app, r) {
            Error(err) -> Error(err)

            Ok(x) -> Ok(list.append(acc, [x]))
          }
          |> list.Continue
      }
    })
  })
}

pub fn sequence_(
  apps apps: List(App(Nil, config, pubsub, user)),
) -> App(Nil, config, pubsub, user) {
  App(fn(r) {
    apps
    |> list.fold_until(Ok(Nil), fn(acc, app) {
      case acc {
        Error(err) ->
          list.Stop(Error(err))

        Ok(_) ->
          case run(app, r) {
            Error(err) ->
              list.Stop(Error(err))

            Ok(_) ->
              list.Continue(Ok(Nil))
          }

      }
    })
  })
}

pub fn replace(
  app app: App(a, config, pubsub, user),
  val val: b,
) -> App(b, config, pubsub, user) {
  App(fn(r) {
    case app.run(r) {
      Ok(_) -> Ok(val)
      Error(e) -> Error(e)
    }
  })
}

pub fn to_result(
  app app: App(a, config, pubsub, user),
  cont cont: fn(Result(a, Err)) -> App(b, config, pubsub, user)
) -> App(b, config, pubsub, user) {
  use ctx <- do(ctx())

  app
  |> run(ctx)
  |> cont
}

// PUBSUB

pub fn subscribe(
  to channel: String,
  in pubsub: fn(pubsub) -> pubsub.PubSub(pubsub_msg),
  wrap to_msg: fn(pubsub_msg) -> msg
) -> App(process.Selector(msg), config, pubsub, user) {
  use ctx <- do(ctx())

  ctx.pubsub
  |> pubsub
  |> pubsub.subscribe(channel:)
  |> process.map_selector(to_msg)
  |> pure
}

pub fn broadcast(
  in pubsub: fn(pubsub) -> pubsub.PubSub(msg),
  to channel: String,
  msg msg: msg,
  cont cont: fn() -> App(t, config, pubsub, user)
) -> App(t, config, pubsub, user) {
  use ctx <- do(ctx())

  ctx.pubsub
  |> pubsub
  |> pubsub.broadcast(channel:, msg:)

  cont()
}

// REDIRECT

pub fn redirect(
  to location: String
) -> App(anything, config, pubsub, user) {
  fail(err.RedirectTo(
    location:,
    using: err.Redirect302,
    flash: None,
    err: None,
  ))
}
