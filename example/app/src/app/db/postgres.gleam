import fpo/types/err
import gleam/option.{type Option}
import fpo/monad/app/db/parrot_postgres as db
import fpo/db/parrot.{type Parrot}
import fpo/monad/app.{type App}
import fpo/monad/app/db/parrot_postgres.{type AppPg} as _
import pog
import app/types.{type Config}
import app/types/err.{type Err} as _

pub fn many(
  parrot parrot: Parrot(t),
) -> AppPg(List(t), Config, pubsub, user, Err)  {
  db.many(parrot:, conn: config_to_conn)
}

pub fn one(
  parrot parrot: Parrot(t),
) -> AppPg(Result(t, Nil), Config, pubsub, user, Err)  {
  db.one(parrot:, conn: config_to_conn)
}

pub fn one_not_many(
  parrot parrot: Parrot(t),
) -> AppPg(Result(t, Option(List(t))), Config, pubsub, user, Err)  {
  db.one_not_many(parrot:, conn: config_to_conn)
}

pub fn one_or(
  parrot parrot: Parrot(t),
  err err: err.Err(Err),
) -> AppPg(t, Config, pubsub, user, Err)  {
  db.one_or(parrot:, conn: config_to_conn, err:)
}

pub fn one_not_many_or(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err.Err(Err),
) -> AppPg(t, Config, pubsub, user, Err)  {
  db.one_not_many_or(parrot:, conn: config_to_conn, err:)
}

fn config_to_conn(
  config config: Config,
) -> pog.Connection {
  config.postgres_conn
}
