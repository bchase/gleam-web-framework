import gleam/option.{type Option}
import fpo/monad/app.{type App, do}
import fpo/types/err
import fpo/db/pog as app_pog
import fpo/db/parrot.{type Parrot}
import pog

pub fn many(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> App(List(t), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.many_postgres(conn: conn(ctx.cfg), to_err:)
  |> app.ok
}

pub fn one(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> App(Result(t, Nil), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_postgres(conn: conn(ctx.cfg), to_err:)
  |> app.ok
}

pub fn one_not_many(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> App(Result(t, Option(List(t))), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_not_many_postgres(conn: conn(ctx.cfg), to_err:)
  |> app.ok
}

pub fn one_or(
  parrot parrot: Parrot(t),
  err err: err.Err(err),
  conn conn: fn(config) -> pog.Connection,
) -> App(t, config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_or_postgres(conn: conn(ctx.cfg), to_err:, err:)
  |> app.ok
}

pub fn one_not_many_or(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err.Err(err),
  conn conn: fn(config) -> pog.Connection,
) -> App(t, config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_not_many_or_postgres(conn: conn(ctx.cfg), to_err:, err:)
  |> app.ok
}

//

fn to_err(
  err err: pog.QueryError,
) -> err.Err(err) {
  err
  |> app_pog.encode_pog_query_error
  |> err.DbErr
}
