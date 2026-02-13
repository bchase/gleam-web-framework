import gleam/result
import gleam/option.{type Option}
import fpo/monad/app.{type App, type AppWithParam, do}
// import fpo/types.{type Context}
import fpo/types/err
import fpo/db/pog as app_pog
import fpo/db/parrot.{type Parrot}
import pog

pub type AppDb(t, config, pubsub, user, err) =
  AppWithParam(t, pog.Connection, config, pubsub, user, err)

pub fn example(
  conn conn: fn(config) -> pog.Connection,
) -> App(#(List(a), List(b)), config, pubsub, user, err) {
  use _ <-do(transaction(conn:, err: todo, app: {
    use xs <- app.do(many_(todo))
    use ys <- app.do(many_(todo))
    app.pure(#(xs, ys))
  }))

  use #(xs, ys) <-do(db(conn:, app: {
    use xs <- app.do(many_(todo))
    use ys <- app.do(many_(todo))
    app.pure(#(xs, ys))
  }))

  app.pure(#(xs, ys))
}

pub fn transaction(
  conn get_conn: fn(config) -> pog.Connection,
  err to_err: fn(pog.TransactionError(err.Err(err))) -> err.Err(err),
  app app: AppDb(t, config, pubsub, user, err),
) -> App(t, config, pubsub, user, err) {
  use ctx <- do(app.ctx())

  ctx.cfg
  |> get_conn
  |> pog.transaction(app.run(app, ctx, _))
  |> result.map_error(to_err)
  |> app.from_result
}

pub fn db(
  conn conn: fn(config) -> pog.Connection,
  app app: AppDb(t, config, pubsub, user, err),
) -> App(t, config, pubsub, user, err) {
  use ctx <- do(app.ctx())

  app
  |> app.run(ctx, conn(ctx.cfg))
  |> app.from_result
}

pub fn many_(
  parrot parrot: Parrot(t),
) -> AppDb(List(t), config, pubsub, user, err) {
  use conn <- do(app.param())

  parrot
  |> parrot.many_postgres(conn:, to_err:)
  |> app.from_result
}


pub fn many(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> App(List(t), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.many_postgres(conn: conn(ctx.cfg), to_err:)
  |> app.from_result
}

pub fn one(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> App(Result(t, Nil), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_postgres(conn: conn(ctx.cfg), to_err:)
  |> app.from_result
}

pub fn one_not_many(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> App(Result(t, Option(List(t))), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_not_many_postgres(conn: conn(ctx.cfg), to_err:)
  |> app.from_result
}

pub fn one_or(
  parrot parrot: Parrot(t),
  err err: err.Err(err),
  conn conn: fn(config) -> pog.Connection,
) -> App(t, config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_or_postgres(conn: conn(ctx.cfg), to_err:, err:)
  |> app.from_result
}

pub fn one_not_many_or(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err.Err(err),
  conn conn: fn(config) -> pog.Connection,
) -> App(t, config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_not_many_or_postgres(conn: conn(ctx.cfg), to_err:, err:)
  |> app.from_result
}

//

fn to_err(
  err err: pog.QueryError,
) -> err.Err(err) {
  err
  |> app_pog.encode_pog_query_error
  |> err.DbErr
}
