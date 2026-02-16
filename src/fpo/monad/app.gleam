import gleam/result
import gleam/crypto
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, Some, None}
import fpo/types.{type Context}
import fpo/context
import fpo/types/err.{type Err}
import fpo/pubsub
import fpo/generic/crypto as fpo_crypto
import fpo/generic/json.{type Transcoders} as _

pub opaque type AppWithParam(t, param, config, pubsub, user, err) {
  AppWithParam(run: fn(Context(config, pubsub, user), param) -> Result(t, Err(err)))
}

pub type App(t, config, pubsub, user, err) =
  AppWithParam(t, Nil, config, pubsub, user, err)

// pub fn run(
//   app app: App(t, config, pubsub, user, err),
//   read read: Context(config, pubsub, user),
// ) -> Result(t, Err(err)) {
//   app.run(read, Nil)
// }

pub fn run(
  app app: AppWithParam(t, param, config, pubsub, user, err),
  read read: Context(config, pubsub, user),
  param param: param,
) -> Result(t, Err(err)) {
  app.run(read, param)
}

pub fn pure(
  val val: t,
) -> AppWithParam(t, param, config, pubsub, user, err) {
  AppWithParam(run: fn(_read, _param) { Ok(val) })
}

pub fn fail(
  err err: Err(err),
) -> AppWithParam(t, param, config, pubsub, user, err) {
  AppWithParam(run: fn(_read, _param) { Error(err) })
}

pub fn ctx(
) -> AppWithParam(Context(config, pubsub, user), param, config, pubsub, user, err) {
  AppWithParam(run: fn(read, _param) { Ok(read) })
}

pub fn param(
) -> AppWithParam(param, param, config, pubsub, user, err) {
  AppWithParam(run: fn(_read, param) { Ok(param) })
}

pub fn map(
  app app: AppWithParam(a, param, config, pubsub, user, err),
  f f: fn(a) -> b,
) -> AppWithParam(b, param, config, pubsub, user, err) {
  AppWithParam(run: fn(read, param) {
    case app.run(read, param) {
      Error(err) -> Error(err)
      Ok(x) -> Ok(f(x))
    }
  })
}

pub fn map_ok(
  app app: AppWithParam(Result(a, e), config, param, pubsub, user, err),
  f f: fn(a) -> b,
) -> AppWithParam(Result(b, e), config, param, pubsub, user, err) {
  app
  |> map(result.map(_, f))
}

pub fn map_some(
  app app: AppWithParam(Option(a), config, param, pubsub, user, err),
  f f: fn(a) -> b,
) -> AppWithParam(Option(b), config, param, pubsub, user, err) {
  app
  |> map(option.map(_, f))
}

pub fn flatten(
  app app: AppWithParam(AppWithParam(t, param, config, pubsub, user, err), param, config, pubsub, user, err),
) -> AppWithParam(t, param, config, pubsub, user, err) {
  AppWithParam(run: fn(read, param) {
    case app.run(read, param) {
      Error(err) -> Error(err)
      Ok(app) -> app.run(read, param)
    }
  })
}

pub fn do(
  app app: AppWithParam(a, param, config, pubsub, user, err),
  cont cont: fn(a) -> AppWithParam(b, param, config, pubsub, user, err),
) -> AppWithParam(b, param, config, pubsub, user, err) {
  // app |> map(cont) |> flatten
  AppWithParam(run: fn(read, param) {
    case app.run(read, param) {
      Error(err) -> Error(err)
      Ok(x) -> cont(x) |> run(read, param)
    }
  })
}

pub fn do_ok(
  app app: AppWithParam(Result(a, e1), param, config, pubsub, user, err),
  err to_err: fn(e1) -> Err(err),
  cont cont: fn(a) -> AppWithParam(b, param, config, pubsub, user, err),
) -> AppWithParam(b, param, config, pubsub, user, err) {
  use result <- do(app)

  case result {
    Ok(x) -> cont(x)
    Error(err) -> fail(to_err(err))
  }
}

pub fn do_(
  app app: AppWithParam(Result(a, e1), param, config, pubsub, user, err),
  fail fail: fn(e1) -> e2,
  cont cont: fn(a) -> AppWithParam(Result(b, e2), param, config, pubsub, user, err),
) -> AppWithParam(Result(b, e2), param, config, pubsub, user, err) {
  use result <- do(app)

  case result {
    Ok(x) -> cont(x)
    Error(err) -> pure(Error(fail(err)))
  }
}

pub fn do__(
  app app: AppWithParam(Result(a, e1), param, config, pubsub, user, err),
  fail err: e2,
  cont cont: fn(a) -> AppWithParam(Result(b, e2), param, config, pubsub, user, err),
) -> AppWithParam(Result(b, e2), param, config, pubsub, user, err) {
  do_(app:, fail: fn(_) { err }, cont:)
}

pub fn ok(
  result result: Result(a, e1),
  err to_err: fn(e1) -> Err(err),
  cont cont: fn(a) -> AppWithParam(b, param, config, pubsub, user, err)
) -> AppWithParam(b, param, config, pubsub, user, err) {
  case result {
    Ok(x) -> cont(x)
    Error(err) -> fail(to_err(err))
  }
}

pub fn ok_(
  result result: Result(a, e1),
  err to_err: fn(e1) -> e2,
  cont cont: fn(a) -> AppWithParam(Result(b, e2), param, config, pubsub, user, err)
) -> AppWithParam(Result(b, e2), param, config, pubsub, user, err) {
  case result {
    Ok(x) -> cont(x)
    Error(err) -> pure(Error(to_err(err)))
  }
}

pub fn ok__(
  result result: Result(a, e1),
  err err: e2,
  cont cont: fn(a) -> AppWithParam(Result(b, e2), param, config, pubsub, user, err)
) -> AppWithParam(Result(b, e2), param, config, pubsub, user, err) {
  case result {
    Ok(x) -> cont(x)
    Error(_) -> pure(Error(err))
  }
}

pub fn some(
  option option: Option(t),
  err err: Err(err),
) -> AppWithParam(t, param, config, pubsub, user, err) {
  AppWithParam(run: fn(_read, _param) {
    option
    |> option.to_result(err)
  })
}

pub fn sequence(
  apps apps: List(AppWithParam(a, param, config, pubsub, user, err)),
) -> AppWithParam(List(a), param, config, pubsub, user, err) {
  AppWithParam(fn(read, param) {
    apps
    |> list.fold_until(Ok([]), fn(acc, app) {
      case acc {
        Error(err) ->
          list.Stop(Error(err))

        Ok(acc) ->
          case app.run(read, param) {
            Error(err) -> Error(err)

            Ok(x) -> Ok(list.append(acc, [x]))
          }
          |> list.Continue
      }
    })
  })
}

pub fn sequence_(
  apps apps: List(AppWithParam(Nil, param, config, pubsub, user, err)),
) -> AppWithParam(Nil, param, config, pubsub, user, err) {
  AppWithParam(fn(read, param) {
    apps
    |> list.fold_until(Ok(Nil), fn(acc, app) {
      case acc {
        Error(err) ->
          list.Stop(Error(err))

        Ok(_) ->
          case app.run(read, param) {
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
  app app: AppWithParam(a, param, config, pubsub, user, err),
  val val: b,
) -> AppWithParam(b, param, config, pubsub, user, err) {
  AppWithParam(fn(read, param) {
    case app.run(read, param) {
      Ok(_) -> Ok(val)
      Error(e) -> Error(e)
    }
  })
}

pub fn from_result(
  result result: Result(t, Err(err)),
) -> AppWithParam(t, param, config, pubsub, user, err) {
  AppWithParam(run: fn(_read, _param) { result })
}

pub fn to_result(
  app app: AppWithParam(a, param, config, pubsub, user, err),
  cont cont: fn(Result(a, Err(err))) -> AppWithParam(b, param, config, pubsub, user, err)
) -> AppWithParam(b, param, config, pubsub, user, err) {
  use ctx <- do(ctx())
  use param <- do(param())

  app
  |> run(ctx, param)
  |> cont
}

// PUBSUB

pub fn subscribe(
  to channel: String,
  in pubsub: fn(pubsub) -> pubsub.PubSub(pubsub_msg),
  wrap to_msg: fn(pubsub_msg) -> msg
) -> AppWithParam(process.Selector(msg), param, config, pubsub, user, err) {
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
  cont cont: fn() -> AppWithParam(t, param, config, pubsub, user, err)
) -> AppWithParam(t, param, config, pubsub, user, err) {
  use ctx <- do(ctx())

  ctx.pubsub
  |> pubsub
  |> pubsub.broadcast(channel:, msg:)

  cont()
}

// REDIRECT

pub fn redirect(
  to location: String
) -> AppWithParam(anything, param, config, pubsub, user, err) {
  fail(err.RedirectTo(
    location:,
    using: err.Redirect302,
    flash: None,
    err: None,
  ))
}

// CRYPTO

const algo = crypto.Sha512

pub fn sign(
  msg msg: t,
  transcoders transcoders: Transcoders(t),
) -> AppWithParam(String, param, config, pubsub, user, err) {
  use result <- do(secret_key_base())

  case result {
    Ok(types.SecretKeyBase(key)) -> pure(fpo_crypto.sign(msg:, transcoders:, key:, algo:))
    Error(Nil) -> fail(err.SecretKeyBaseLookupFailed)
  }
}

pub fn verify(
  msg msg: String,
  transcoders transcoders: Transcoders(t),
) -> AppWithParam(Result(t, Nil), param, config, pubsub, user, err) {
  use result <- do(secret_key_base())

  case result {
    Ok(types.SecretKeyBase(key)) -> pure(fpo_crypto.verify(msg:, transcoders:, key:))
    Error(Nil) -> fail(err.SecretKeyBaseLookupFailed)
  }
}

fn secret_key_base(
) -> AppWithParam(Result(types.SecretKeyBase, Nil), param, config, pubsub, user, err) {
  use ctx <- do(ctx())
  pure(context.secret_key_base(ctx))
}

// USER

pub fn user(
) -> AppWithParam(user, param, config, pubsub, user, err) {
  use ctx <- do(ctx())

  case ctx.user {
    Some(user) -> pure(user)
    None -> fail(err.Unauthenticated)
  }
}
