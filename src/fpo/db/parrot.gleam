import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/result
import parrot/dev as parrot

pub type Param = parrot.Param

pub type Parrot(t) = #(String, List(parrot.Param), Decoder(t))

pub type ParrotExec = #(String, List(parrot.Param))

pub type Db(t, conn, db_param, db_err, err) {
  Db(
    query: QueryFunc(t, conn, db_param, db_err),
    to_param: fn(Param) -> db_param,
    to_err: fn(db_err) -> err,
  )
}

type QueryFunc(t, conn, db_param, db_err) =
  fn(String, conn, List(db_param), Decoder(t)) -> Result(List(t), db_err)

pub fn exec(
  parrot parrot: ParrotExec,
  conn conn: conn,
  db db: Db(Nil, conn, db_param, db_err, err),
) -> Result(Nil, err)  {
  let #(sql, params) = parrot
  let params = params |> list.map(db.to_param)
  let decoder = decode.success(Nil)

  db.query(sql, conn, params, decoder)
  |> result.map_error(db.to_err)
  |> result.replace(Nil)
}

pub fn many(
  parrot parrot: Parrot(t),
  conn conn: conn,
  db db: Db(t, conn, db_param, db_err, err),
) -> Result(List(t), err) {
  let #(sql, params, decoder) = parrot

  params
  |> list.map(db.to_param)
  |> db.query(sql, conn, _, decoder)
  |> result.map_error(db.to_err)
}

pub fn one(
  parrot parrot: Parrot(t),
  conn conn: conn,
  db db: Db(t, conn, db_param, db_err, err),
) -> Result(Result(t, Nil), err)  {
  case many(parrot, conn, db) {
    Error(err) -> Error(err)
    Ok([]) ->  Ok(Error(Nil))
    Ok([x, ..]) -> Ok(Ok(x))
  }
}

pub fn one_not_many(
  parrot parrot: Parrot(t),
  conn conn: conn,
  db db: Db(t, conn, db_param, db_err, err),
) -> Result(Result(t, Option(List(t))), err)  {
  case many(parrot:, conn:, db:) {
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
  db db: Db(t, conn, db_param, db_err, err),
) -> Result(t, err)  {
  case many(parrot:, conn:, db:) {
    Ok([x, ..]) -> Ok(x)
    Ok([]) ->  Error(err)
    Error(err) -> Error(err)
  }
}

pub fn one_not_many_or(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err,
  conn conn: conn,
  db db: Db(t, conn, db_param, db_err, err),
) -> Result(t, err)  {
  case many(parrot:, conn:, db:) {
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
