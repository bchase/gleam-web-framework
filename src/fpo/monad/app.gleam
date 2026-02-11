import gleam/crypto
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import fpo/types.{type Context}
import fpo/context
import fpo/types/err.{type Err}
import fpo/pubsub
import fpo/generic/crypto as fpo_crypto
import fpo/generic/json.{type Transcoders} as _

pub opaque type App(t, config, pubsub, user, err) {
  App(run: fn(Context(config, pubsub, user)) -> Result(t, Err(err)))
}

pub fn run(
  app app: App(t, config, pubsub, user, err),
  read read: Context(config, pubsub, user),
) -> Result(t, Err(err)) {
  app.run(read)
}

pub fn pure(
  val val: t,
) -> App(t, config, pubsub, user, err) {
  App(run: fn(_read) { Ok(val) })
}

pub fn fail(
  err err: Err(err),
) -> App(t, config, pubsub, user, err) {
  App(run: fn(_read) { Error(err) })
}

pub fn ctx() -> App(Context(config, pubsub, user), config, pubsub, user, err) {
  App(run: fn(read) { Ok(read) })
}

pub fn map(
  app app: App(a, config, pubsub, user, err),
  f f: fn(a) -> b,
) -> App(b, config, pubsub, user, err) {
  App(run: fn(read) {
    case app.run(read) {
      Error(err) -> Error(err)
      Ok(x) -> Ok(f(x))
    }
  })
}

pub fn flatten(
  app app: App(App(t, config, pubsub, user, err), config, pubsub, user, err),
) -> App(t, config, pubsub, user, err) {
  App(run: fn(read) {
    case app.run(read) {
      Error(err) -> Error(err)
      Ok(app) -> app.run(read)
    }
  })
}

pub fn do(
  app app: App(a, config, pubsub, user, err),
  cont cont: fn(a) -> App(b, config, pubsub, user, err),
) -> App(b, config, pubsub, user, err) {
  // app |> map(cont) |> flatten
  App(run: fn(read) {
    case app.run(read) {
      Error(err) -> Error(err)
      Ok(x) -> cont(x) |> run(read)
    }
  })
}

pub fn do_ok(
  app app: App(Result(a, e1), config, pubsub, user, err),
  err to_err: fn(e1) -> Err(err),
  cont cont: fn(a) -> App(b, config, pubsub, user, err),
) -> App(b, config, pubsub, user, err) {
  use result <- do(app)

  case result {
    Ok(x) -> cont(x)
    Error(err) -> fail(to_err(err))
  }
}

pub fn do_(
  app app: App(Result(a, e1), config, pubsub, user, err),
  fail fail: fn(e1) -> e2,
  cont cont: fn(a) -> App(Result(b, e2), config, pubsub, user, err),
) -> App(Result(b, e2), config, pubsub, user, err) {
  use result <- do(app)

  case result {
    Ok(x) -> cont(x)
    Error(err) -> pure(Error(fail(err)))
  }
}

pub fn do__(
  app app: App(Result(a, e1), config, pubsub, user, err),
  fail err: e2,
  cont cont: fn(a) -> App(Result(b, e2), config, pubsub, user, err),
) -> App(Result(b, e2), config, pubsub, user, err) {
  do_(app:, fail: fn(_) { err }, cont:)
}

pub fn ok(
  result result: Result(a, e1),
  err to_err: fn(e1) -> Err(err),
  cont cont: fn(a) -> App(b, config, pubsub, user, err)
) -> App(b, config, pubsub, user, err) {
  case result {
    Ok(x) -> cont(x)
    Error(err) -> fail(to_err(err))
  }
}

pub fn ok_(
  result result: Result(a, e1),
  err to_err: fn(e1) -> e2,
  cont cont: fn(a) -> App(Result(b, e2), config, pubsub, user, err)
) -> App(Result(b, e2), config, pubsub, user, err) {
  case result {
    Ok(x) -> cont(x)
    Error(err) -> pure(Error(to_err(err)))
  }
}

pub fn ok__(
  result result: Result(a, e1),
  err err: e2,
  cont cont: fn(a) -> App(Result(b, e2), config, pubsub, user, err)
) -> App(Result(b, e2), config, pubsub, user, err) {
  case result {
    Ok(x) -> cont(x)
    Error(_) -> pure(Error(err))
  }
}

pub fn some(
  option option: Option(t),
  err err: Err(err),
) -> App(t, config, pubsub, user, err) {
  App(run: fn(_read) {
    option
    |> option.to_result(err)
  })
}

pub fn sequence(
  apps apps: List(App(a, config, pubsub, user, err)),
) -> App(List(a), config, pubsub, user, err) {
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
  apps apps: List(App(Nil, config, pubsub, user, err)),
) -> App(Nil, config, pubsub, user, err) {
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
  app app: App(a, config, pubsub, user, err),
  val val: b,
) -> App(b, config, pubsub, user, err) {
  App(fn(r) {
    case app.run(r) {
      Ok(_) -> Ok(val)
      Error(e) -> Error(e)
    }
  })
}

pub fn from_result(
  result result: Result(t, Err(err)),
) -> App(t, config, pubsub, user, err) {
  App(run: fn(_read) { result })
}

pub fn to_result(
  app app: App(a, config, pubsub, user, err),
  cont cont: fn(Result(a, Err(err))) -> App(b, config, pubsub, user, err)
) -> App(b, config, pubsub, user, err) {
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
) -> App(process.Selector(msg), config, pubsub, user, err) {
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
  cont cont: fn() -> App(t, config, pubsub, user, err)
) -> App(t, config, pubsub, user, err) {
  use ctx <- do(ctx())

  ctx.pubsub
  |> pubsub
  |> pubsub.broadcast(channel:, msg:)

  cont()
}

// REDIRECT

pub fn redirect(
  to location: String
) -> App(anything, config, pubsub, user, err) {
  fail(err.RedirectTo(
    location:,
    using: err.Redirect302,
    flash: None,
    err: None,
  ))
}

//

const algo = crypto.Sha512

pub fn sign(
  msg msg: t,
  transcoders transcoders: Transcoders(t),
) -> App(String, config, pubsub, user, err) {
  use result <- do(secret_key_base())

  case result {
    Ok(types.SecretKeyBase(key)) -> pure(fpo_crypto.sign(msg:, transcoders:, key:, algo:))
    Error(Nil) -> fail(err.SecretKeyBaseLookupFailed)
  }
}

pub fn verify(
  msg msg: String,
  transcoders transcoders: Transcoders(t),
) -> App(Result(t, Nil), config, pubsub, user, err) {
  use result <- do(secret_key_base())

  case result {
    Ok(types.SecretKeyBase(key)) -> pure(fpo_crypto.verify(msg:, transcoders:, key:))
    Error(Nil) -> fail(err.SecretKeyBaseLookupFailed)
  }
}

fn secret_key_base(
) -> App(Result(types.SecretKeyBase, Nil), config, pubsub, user, err) {
  use ctx <- do(ctx())
  pure(context.secret_key_base(ctx))
}
