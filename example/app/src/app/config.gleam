import gleam/erlang/process
import gleam/result
import gleam/dynamic/decode
import gleam/string
import gleam/option.{Some}
import gleam/otp/static_supervisor
import fpo/pubsub
import fpo/types.{type Flags} as _
import pog
import sqlight
import app/types.{type Config, type PubSub, Config, PubSub}
//
import app/user
import gleam/bit_array

const sqlite_db_path = "./app-sqlite3.db"
const postgres_conn_url = "postgres://webapp:webapp@127.0.0.1:5432/app_gleam"

pub fn add_pubsub_workers(
  supervisor supervisor: static_supervisor.Builder,
) -> #(static_supervisor.Builder, PubSub) {
  // let #(supervisor, text) =
  //   supervisor
  //   |> pubsub.add_cluster_worker(
  //     name: "text",
  //     app_module_name: spec.app_module_name,
  //     transcoders: spec_pubsub.text_transcoders,
  //   )

  let #(supervisor, text) = supervisor |> pubsub.add_local_node_only_worker(name: "text")

  let pubsub = PubSub(text:)

  #(supervisor, pubsub)
}

pub fn init(
  flags flags: Flags,
) -> Config {
  let assert Some(cloak) = flags.cloak

  let sqlite_conn = connect_to_sqlite_and_migrate()
  let postgres_conn = connect_to_postgres()
  // let postgres_conn = connect_to_postgres_and_migrate()

  Config(
    cloak:,
    sqlite_conn:,
    postgres_conn:,
  )
}

//

fn connect_to_sqlite_and_migrate() -> sqlight.Connection {
  let conn = connect_to_sqlite()

  let result = "
    create table if not exists msgs (
      id integer not null primary key autoincrement,
      msg text not null
    );
  " |> sqlight.query(conn, [], decode.success(Nil))

  let assert Ok(_migrated) = result as "migrated sqlite `msgs` table"

  let result = "
    create table if not exists users (
      id integer not null primary key autoincrement,
      name text not null
    );
  " |> sqlight.query(conn, [], decode.success(Nil))

  let assert Ok(_migrated) = result as "migrated sqlite `users` table"

  let result = "
    create table if not exists user_tokens (
      id integer not null primary key autoincrement,
      hashed_token text not null,
      context text not null,
      user_id integer not null references users(id)
    );
  " |> sqlight.query(conn, [], decode.success(Nil))

  let assert Ok(_migrated) = result as "migrated sqlite `user_tokens` table"

  let result = "
    create table if not exists users (
      id integer not null primary key autoincrement,
      name text not null
    );
  " |> sqlight.query(conn, [], decode.success(Nil))

  let assert Ok(_migrated) = result as "migrated sqlite `users` table"

  //

  let result = "
    delete from users;
  " |> sqlight.query(conn, [], decode.success(Nil))

  let assert Ok(_deleted) = result as "deleted `users`"

  let result = "
    insert into users ( id, name ) values ( 1, 'Buddy' );
  " |> sqlight.query(conn, [], decode.success(Nil))

  let assert Ok(_inserted) = result as "inserted sqlite `users` row"

  //

  let result = "
    delete from user_tokens;
  " |> sqlight.query(conn, [], decode.success(Nil))

  let assert Ok(_deleted) = result as "deleted `users`"

  let hashed_token =
    user.dummy_token_hashed_for_db()

  let result = { "
    insert into user_tokens ( id, hashed_token, context, user_id )
    values ( 1, '" <> hashed_token <> "', 'session', 1 );
  " } |> sqlight.query(conn, [], decode.success(Nil))

  let assert Ok(_inserted) = result as "inserted sqlite `users` row"

  conn
}

fn connect_to_sqlite() -> sqlight.Connection {
  case sqlight.open(sqlite_db_path) {
    Ok(conn) ->
      conn

    Error(err) ->
      panic as { [
        "`connect_to_sqlite` failed:", string.inspect(err),
        "Please check that a sqlite3 db exists at:", sqlite_db_path,
      ] |> string.join(" ")}
  }
}

//

fn connect_to_postgres_and_migrate() -> pog.Connection {
  let conn = connect_to_postgres()

  let result = "
    create table if not exists msgs (
      id serial not null primary key,
      msg text not null
    );
  " |> pog.query
    |> pog.execute(conn)

  todo as "postgres migrate `users` table & insert user"

  let assert Ok(_migrated) = result as "migrated postgres database"

  conn
}

fn connect_to_postgres() -> pog.Connection {
  {
    let name = process.new_name("pog")
    use cfg <- result.try(pog.url_config(name, postgres_conn_url))
    let assert Ok(db) = pog.start(cfg) as "started postgres (pog)"
    Ok(db.data)
  }
  |> fn(result) {
    case result {
      Ok(conn) ->
        conn

      Error(err) ->
        panic as { [
          "`connect_to_postgres` failed:", string.inspect(err),
          "Please check that a postgres db exists at:", postgres_conn_url,
        ] |> string.join(" ") }
    }
  }
 }
