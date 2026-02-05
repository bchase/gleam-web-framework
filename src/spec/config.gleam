import gleam/io
import gleam/erlang/process
import gleam/result
import gleam/dynamic/decode
import gleam/string
import app/oauth
import app/oauth/oura
import gleam/option.{type Option, None}
import gleam/otp/static_supervisor
import app/pubsub
import app/types.{type Session}
import spec/pubsub.{type TextMsg} as _
import spec/user.{type User}
import pog
import sqlight

const sqlite_db_path = "./app-sqlite3.db"
const postgres_conn_url = "postgres://webapp:webapp@127.0.0.1:5432/app_gleam"

pub fn authenticate(
  session _session: Session,
  cfg _cfg: Config,
) -> Option(User) {
  None
}

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

pub type Config {
  Config(
    sqlite_conn: sqlight.Connection,
    postgres_conn: pog.Connection,
    oura_oauth: oauth.Config,
  )
}

pub type PubSub {
  PubSub(
    text: pubsub.PubSub(TextMsg),
  )
}

pub fn init_config() -> Config {
  let sqlite_conn = connect_to_sqlite_and_migrate()
  let postgres_conn = connect_to_postgres_and_migrate()
  let oura_oauth = oura.build_config()

  Config(
    sqlite_conn:,
    postgres_conn:,
    oura_oauth:,
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

  let assert Ok(_migrated) = result as "migrated sqlite database"

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
      id integer not null primary key,
      msg text not null
    );
  " |> pog.query
    |> pog.execute(conn)

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
