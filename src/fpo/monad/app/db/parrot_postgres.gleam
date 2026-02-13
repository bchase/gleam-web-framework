import gleam/option.{type Option}
import fpo/monad/app.{type App, type AppWithParam, do}
// import fpo/types.{type Context}
import fpo/types/err
import fpo/db/pog as app_pog
import fpo/db/parrot.{type Parrot}
import pog

pub type AppDb(t, config, pubsub, user, err) =
  AppWithParam(t, pog.Connection, config, pubsub, user, err)

pub fn many_(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> AppDb(List(t), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())
  use param <- do(app.param())

  parrot
  |> parrot.many_postgres(conn: conn(ctx.cfg), to_err:)
  |> app.from_result

  todo
}

// pub opaque type AppTransaction(t, config, pubsub, user, err) {
//   AppTransaction(
//     app: fn(pog.Connection) -> App(t, config, pubsub, user, err),
//     // conn: pog.Connection,
//   )
// }

// pub fn transaction(
//   ctx ctx: Context(config, pubsub, user),
//   conn conn: fn(config) -> pog.Connection,
// ) -> AppTransaction(Nil, config, pubsub, user, err)  {
//   let conn = conn(ctx.cfg)

//   pog.transaction(conn, fn(conn) {
//   })

//   parrot
//   |> parrot.many_postgres(conn:, to_err:)
//   |> app.from_result
//   |> todo
// }

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
