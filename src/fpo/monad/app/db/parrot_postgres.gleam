import gleam/list
import gleam/dynamic/decode.{type Decoder}
import gleam/result
import gleam/option.{type Option}
import fpo/monad/app.{type App, type AppWithParam, do}
// import fpo/types.{type Context}
import fpo/types/err
import fpo/db/pog as app_pog
import fpo/db/parrot.{type Parrot, type Db, Db}
import parrot/dev as p
import pog

pub type AppPg(t, config, pubsub, user, err) =
  AppWithParam(t, pog.Connection, config, pubsub, user, err)

pub fn pg(
  to_err to_err: fn(pog.QueryError) -> err,
) -> Db(t, pog.Connection, pog.Value, pog.QueryError, err) {
  Db(
    query: pog_query,
    to_param: parrot_to_pog,
    to_err:,
  )
}

// pub fn example(
//   conn conn: fn(config) -> pog.Connection,
//   err err: fn(pog.TransactionError(err.Err(err))) -> err.Err(err),
// ) -> App(#(List(a), List(b)), config, pubsub, user, err) {
//   use t <- do(db_transaction(conn:, err:, app: {
//     use xs <- do(many(todo, conn:))
//     use ys <- do(many(todo, conn:))
//     app.pure(#(xs, ys))
//   }))

//   app.pure(t)
// }

pub fn db(
  conn conn: fn(config) -> pog.Connection,
  app app: AppPg(t, config, pubsub, user, err),
) -> App(t, config, pubsub, user, err) {
  use ctx <- do(app.ctx())

  app
  |> app.run(ctx, conn(ctx.cfg))
  |> app.from_result
}

pub fn db_transaction(
  conn get_conn: fn(config) -> pog.Connection,
  err to_err: fn(pog.TransactionError(err.Err(err))) -> err.Err(err),
  app app: AppPg(t, config, pubsub, user, err),
) -> App(t, config, pubsub, user, err) {
  use ctx <- do(app.ctx())

  ctx.cfg
  |> get_conn
  |> pog.transaction(app.run(app, ctx, _))
  |> result.map_error(to_err)
  |> app.from_result
}

//

pub fn many(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> AppPg(List(t), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.many(conn: conn(ctx.cfg), db: pg(to_err:))
  |> app.from_result
}

pub fn one(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> AppPg(Result(t, Nil), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one(conn: conn(ctx.cfg), db: pg(to_err:))
  |> app.from_result
}

pub fn one_not_many(
  parrot parrot: Parrot(t),
  conn conn: fn(config) -> pog.Connection,
) -> AppPg(Result(t, Option(List(t))), config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_not_many(conn: conn(ctx.cfg), db: pg(to_err:))
  |> app.from_result
}

pub fn one_or(
  parrot parrot: Parrot(t),
  err err: err.Err(err),
  conn conn: fn(config) -> pog.Connection,
) -> AppPg(t, config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_or(err:, conn: conn(ctx.cfg), db: pg(to_err:))
  |> app.from_result
}

pub fn one_not_many_or(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err.Err(err),
  conn conn: fn(config) -> pog.Connection,
) -> AppPg(t, config, pubsub, user, err)  {
  use ctx <- do(app.ctx())

  parrot
  |> parrot.one_not_many_or(err:, conn: conn(ctx.cfg), db: pg(to_err:))
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

//

pub fn parrot_to_pog(
  param: parrot.Param,
) -> pog.Value {
  case param {
    p.ParamBool(x) -> pog.bool(x)
    p.ParamFloat(x) -> pog.float(x)
    p.ParamInt(x) -> pog.int(x)
    p.ParamString(x) -> pog.text(x)
    p.ParamBitArray(x) -> pog.bytea(x)
    p.ParamList(x) -> pog.array(parrot_to_pog, x)
    p.ParamNullable(x) -> pog.nullable(parrot_to_pog, x)
    p.ParamDate(x) -> pog.calendar_date(x)
    p.ParamTimestamp(x) -> pog.timestamp(x)
    //
    p.ParamDynamic(_) -> panic as "cannot process dynamic parameter"
  }
}

fn pog_query(
  sql sql: String,
  conn conn: pog.Connection,
  params params: List(pog.Value),
  decoder decoder: decode.Decoder(t),
) -> Result(List(t), pog.QueryError) {
  sql
  |> pog.query
  |> pog.returning(decoder)
  |> list.fold(params, _, fn(acc, param) {
    pog.parameter(acc, param)
  })
  |> pog.execute(conn)
  |> result.map(fn(returned) { returned.rows })
}
