import gleam/option.{type Option}
import fpo/monad/app.{type App, type AppWithParam, do}
import fpo/types/err
import fpo/db/sqlight as app_sqlight
import fpo/db/parrot.{type Parrot, type Db, Db}
import sqlight
import parrot/dev as p

pub type AppSqlite(t, config, pubsub, user, err) =
  AppWithParam(t, sqlight.Connection, config, pubsub, user, err)

pub fn sqlite(
  to_err to_err: fn(sqlight.Error) -> err,
) -> Db(t, sqlight.Connection, sqlight.Value, sqlight.Error, err) {
  Db(
    query: sqlight.query,
    to_param: parrot_to_sqlight,
    to_err:,
  )
}

pub fn db(
  conn conn: fn(config) -> sqlight.Connection,
  app app: AppSqlite(t, config, pubsub, user, err),
) -> App(t, config, pubsub, user, err) {
  use ctx <- do(app.ctx())

  app
  |> app.run(ctx, conn(ctx.cfg))
  |> app.from_result
}

// pub fn db_transaction(
//   conn conn: fn(config) -> sqlight.Connection,
//   app app: AppSqlite(t, config, pubsub, user, err),
// ) -> App(t, config, pubsub, user, err) {
//   use ctx <- do(app.ctx())
//   let conn = conn(ctx.cfg)

//   todo

//   app
//   |> app.run(ctx, conn)
//   |> app.from_result
// }

//

pub fn many(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> sqlight.Connection,
) -> App(List(t), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.many(conn: conn(ctx.cfg), db: sqlite(to_err:))
  |> app.from_result
}

pub fn one(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> sqlight.Connection,
) -> App(Result(t, Nil), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one(conn: conn(ctx.cfg), db: sqlite(to_err:))
  |> app.from_result
}

pub fn one_not_many(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> sqlight.Connection,
) -> App(Result(t, Option(List(t))), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_not_many(conn: conn(ctx.cfg), db: sqlite(to_err:))
  |> app.from_result
}

pub fn one_or(
  parrot parrot: Parrot(t),
  err err: err.Err(err),
  conn conn: fn(config) -> sqlight.Connection,
) -> App(t, config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_or(err:, conn: conn(ctx.cfg), db: sqlite(to_err:))
  |> app.from_result
}

pub fn one_not_many_or(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err.Err(err),
  conn conn: fn(config) -> sqlight.Connection,
) -> App(t, config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_not_many_or(err:, conn: conn(ctx.cfg), db: sqlite(to_err:))
  |> app.from_result
}

//

fn to_err(
  err err: sqlight.Error,
) -> err.Err(err) {
  err
  |> app_sqlight.encode_sqlight_error
  |> err.DbErr
}

//

pub fn parrot_to_sqlight(
  param: parrot.Param,
) -> sqlight.Value {
  case param {
    p.ParamBool(x) -> sqlight.bool(x)
    p.ParamFloat(x) -> sqlight.float(x)
    p.ParamInt(x) -> sqlight.int(x)
    p.ParamString(x) -> sqlight.text(x)
    p.ParamBitArray(x) -> sqlight.blob(x)
    p.ParamNullable(x) -> sqlight.nullable(fn(a) { parrot_to_sqlight(a) }, x)
    //
    p.ParamDate(_) -> panic as "date parameter needs to be implemented"
    p.ParamTimestamp(_) -> panic as "sqlite does not support timestamps"
    //
    p.ParamList(_) -> panic as "sqlite does not implement lists"
    p.ParamDynamic(_) -> panic as "cannot process dynamic parameter"
  }
}
