import app/types/err
import gleam/option.{type Option}
import app/monad/app/db/parrot_sqlite as db
import app/db/parrot.{type Parrot}
import app/monad/app.{type App}
import sqlight
import spec/config.{type Config}

pub fn many(
  parrot parrot: Parrot(t),
) -> App(List(t), Config, pubsub, user)  {
  db.many(parrot:, conn: config_to_conn)
}

pub fn one(
  parrot parrot: Parrot(t),
) -> App(Result(t, Nil), Config, pubsub, user)  {
  db.one(parrot:, conn: config_to_conn)
}

pub fn one_not_many(
  parrot parrot: Parrot(t),
) -> App(Result(t, Option(List(t))), Config, pubsub, user)  {
  db.one_not_many(parrot:, conn: config_to_conn)
}

pub fn one_or(
  parrot parrot: Parrot(t),
  err err: err.Err,
) -> App(t, Config, pubsub, user)  {
  db.one_or(parrot:, conn: config_to_conn, err:)
}

pub fn one_not_many_or(
  parrot parrot: Parrot(t),
  err err: fn(Option(List(t))) -> err.Err,
) -> App(t, Config, pubsub, user)  {
  db.one_not_many_or(parrot:, conn: config_to_conn, err:)
}

fn config_to_conn(
  config config: Config,
) -> sqlight.Connection {
  todo
}
