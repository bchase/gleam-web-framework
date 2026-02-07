import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/result
import parrot/dev as parrot
import pog
import sqlight

pub type Param = parrot.Param

pub type Parrot(t) = #(String, List(parrot.Param), Decoder(t))

pub type ParrotExec = #(String, List(parrot.Param))

//

pub fn many_postgres(
  parrot parrot: Parrot(t),
  conn conn: pog.Connection,
  to_err to_err: fn(pog.QueryError) -> err,
) -> Result(List(t), err)  {
  many(parrot:, conn:, query: pog_query, to_param: parrot_to_pog, to_err:)
}

pub fn one_postgres(
  parrot parrot: Parrot(t),
  conn conn: pog.Connection,
  to_err to_err: fn(pog.QueryError) -> err,
) -> Result(Result(t, Nil), err)  {
  one(parrot:, conn:, query: pog_query, to_param: parrot_to_pog, to_err:)
}

pub fn one_not_many_postgres(
  parrot parrot: Parrot(t),
  conn conn: pog.Connection,
  to_err to_err: fn(pog.QueryError) -> err,
) -> Result(Result(t, Option(List(t))), err)  {
  one_not_many(parrot:, conn:, query: pog_query, to_param: parrot_to_pog, to_err:)
}

pub fn one_or_postgres(
  parrot parrot: Parrot(t),
  err err: err,
  conn conn: pog.Connection,
  to_err to_err: fn(pog.QueryError) -> err,
) -> Result(t, err)  {
  one_or(parrot:, err:, conn:, query: pog_query, to_param: parrot_to_pog, to_err:)
}

pub fn one_not_many_or_postgres(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err,
  conn conn: pog.Connection,
  to_err to_err: fn(pog.QueryError) -> err,
) -> Result(t, err)  {
  one_not_many_or(parrot:, err:, conn:, query: pog_query, to_param: parrot_to_pog, to_err:)
}

//

pub fn many_sqlite(
  parrot parrot: Parrot(t),
  conn conn: sqlight.Connection,
  to_err to_err: fn(sqlight.Error) -> err,
) -> Result(List(t), err)  {
  many(parrot:, conn:, query: sqlight.query, to_param: parrot_to_sqlight, to_err:)
}

pub fn one_sqlite(
  parrot parrot: Parrot(t),
  conn conn: sqlight.Connection,
  to_err to_err: fn(sqlight.Error) -> err,
) -> Result(Result(t, Nil), err)  {
  one(parrot:, conn:, query: sqlight.query, to_param: parrot_to_sqlight, to_err:)
}

pub fn one_not_many_sqlite(
  parrot parrot: Parrot(t),
  conn conn: sqlight.Connection,
  to_err to_err: fn(sqlight.Error) -> err,
) -> Result(Result(t, Option(List(t))), err)  {
  one_not_many(parrot:, conn:, query: sqlight.query, to_param: parrot_to_sqlight, to_err:)
}

pub fn one_or_sqlite(
  parrot parrot: Parrot(t),
  err err: err,
  conn conn: sqlight.Connection,
  to_err to_err: fn(sqlight.Error) -> err,
) -> Result(t, err)  {
  one_or(parrot:, err:, conn:, query: sqlight.query, to_param: parrot_to_sqlight, to_err:)
}

pub fn one_not_many_or_sqlite(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err,
  conn conn: sqlight.Connection,
  to_err to_err: fn(sqlight.Error) -> err,
) -> Result(t, err)  {
  one_not_many_or(parrot:, err:, conn:, query: sqlight.query, to_param: parrot_to_sqlight, to_err:)
}

//

pub fn exec(
  parrot parrot: ParrotExec,
  conn conn: conn,
  query query: fn(String, conn, List(db_param), Decoder(Nil)) -> Result(List(Nil), db_err),
  to_param to_param: fn(parrot.Param) -> db_param,
  to_err to_err: fn(db_err) -> err,
) -> Result(Nil, err)  {
  let #(sql, params) = parrot
  let params = params |> list.map(to_param)
  let decoder = decode.success(Nil)

  query(sql, conn, params, decoder)
  |> result.map_error(to_err)
  |> result.replace(Nil)
}

pub fn many(
  parrot parrot: Parrot(t),
  conn conn: conn,
  query query: fn(String, conn, List(db_param), Decoder(t)) -> Result(List(t), db_err),
  to_param to_param: fn(parrot.Param) -> db_param,
  to_err to_err: fn(db_err) -> err,
) -> Result(List(t), err)  {
  let #(sql, params, decoder) = parrot

  params
  |> list.map(to_param)
  |> query(sql, conn, _, decoder)
  |> result.map_error(to_err)
}

pub fn one(
  parrot parrot: Parrot(t),
  conn conn: conn,
  query query: fn(String, conn, List(db_param), Decoder(t)) -> Result(List(t), db_err),
  to_param to_param: fn(parrot.Param) -> db_param,
  to_err to_err: fn(db_err) -> err,
) -> Result(Result(t, Nil), err)  {
  case many(parrot:, conn:, query:, to_param:, to_err:) {
    Error(err) -> Error(err)
    Ok([]) ->  Ok(Error(Nil))
    Ok([x, ..]) -> Ok(Ok(x))
  }
}

pub fn one_not_many(
  parrot parrot: Parrot(t),
  conn conn: conn,
  query query: fn(String, conn, List(db_param), Decoder(t)) -> Result(List(t), db_err),
  to_param to_param: fn(parrot.Param) -> db_param,
  to_err to_err: fn(db_err) -> err,
) -> Result(Result(t, Option(List(t))), err)  {
  case many(parrot:, conn:, query:, to_param:, to_err:) {
    Ok([x]) -> Ok(Ok(x))
    Ok([]) ->  Ok(Error(None))
    Ok(xs) -> Ok(Error(Some(xs)))
    Error(err) -> Error(err)
  }
}

pub fn one_or(
  parrot parrot: Parrot(t),
  err err: err,
  conn conn: conn,
  query query: fn(String, conn, List(db_param), Decoder(t)) -> Result(List(t), db_err),
  to_param to_param: fn(parrot.Param) -> db_param,
  to_err to_err: fn(db_err) -> err,
) -> Result(t, err)  {
  case many(parrot:, conn:, query:, to_param:, to_err:) {
    Ok([x, ..]) -> Ok(x)
    Ok([]) ->  Error(err)
    Error(err) -> Error(err)
  }
}

pub fn one_not_many_or(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err,
  conn conn: conn,
  query query: fn(String, conn, List(db_param), Decoder(t)) -> Result(List(t), db_err),
  to_param to_param: fn(parrot.Param) -> db_param,
  to_err to_err: fn(db_err) -> err,
) -> Result(t, err)  {
  case many(parrot:, conn:, query:, to_param:, to_err:) {
    Ok([x]) -> Ok(x)
    Ok([]) ->  Error(err(None))
    Ok(xs) -> Error(err(Some(xs)))
    Error(err) -> Error(err)
  }
}

//

pub fn from_exec(
  parrot parrot: ParrotExec,
) -> Parrot(Nil)  {
  let #(sql, params) = parrot
  let decoder = decode.success(Nil)

  #(sql, params, decoder)
}

//

pub fn parrot_to_sqlight(
  param: parrot.Param,
) -> sqlight.Value {
  case param {
    parrot.ParamBool(x) -> sqlight.bool(x)
    parrot.ParamFloat(x) -> sqlight.float(x)
    parrot.ParamInt(x) -> sqlight.int(x)
    parrot.ParamString(x) -> sqlight.text(x)
    parrot.ParamBitArray(x) -> sqlight.blob(x)
    parrot.ParamNullable(x) -> sqlight.nullable(fn(a) { parrot_to_sqlight(a) }, x)
    //
    parrot.ParamDate(_) -> panic as "date parameter needs to be implemented"
    parrot.ParamTimestamp(_) -> panic as "sqlite does not support timestamps"
    //
    parrot.ParamList(_) -> panic as "sqlite does not implement lists"
    parrot.ParamDynamic(_) -> panic as "cannot process dynamic parameter"
  }
}

//

pub fn parrot_to_pog(
  param: parrot.Param,
) -> pog.Value {
  case param {
    parrot.ParamBool(x) -> pog.bool(x)
    parrot.ParamFloat(x) -> pog.float(x)
    parrot.ParamInt(x) -> pog.int(x)
    parrot.ParamString(x) -> pog.text(x)
    parrot.ParamBitArray(x) -> pog.bytea(x)
    parrot.ParamList(x) -> pog.array(parrot_to_pog, x)
    parrot.ParamNullable(x) -> pog.nullable(parrot_to_pog, x)
    parrot.ParamDate(x) -> pog.calendar_date(x)
    parrot.ParamTimestamp(x) -> pog.timestamp(x)
    //
    parrot.ParamDynamic(_) -> panic as "cannot process dynamic parameter"
  }
}

fn pog_query(
  sql sql: String,
  conn conn: pog.Connection,
  params params: List(pog.Value),
  decoder decoder: decode.Decoder(t),
) -> Result(List(t), pog.QueryError) {
  sql
  |> pog.query()
  |> pog.returning(decoder)
  |> list.fold(params, _, fn(acc, param) {
    pog.parameter(acc, param)
  })
  |> pog.execute(conn)
  |> result.map(fn(returned) { returned.rows })
}
