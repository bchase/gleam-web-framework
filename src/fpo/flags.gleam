import gleam/pair
import gleam/list
import gleam/erlang/process
import gleam/option.{Some, None}
import gleam/otp/static_supervisor
import gleam/otp/supervision
import fpo/types.{type Features, type Flags, Flags, type EnvVar}
import cloak_wrapper/store as cloak_store
import fpo/cloak.{Cloak}
import fpo/generic/guard
import pog

pub fn build(
  features features: Features,
  env_var env_var: EnvVar
) -> #(Flags, List(fn(static_supervisor.Builder) -> static_supervisor.Builder)) {
  let flags = Flags(env_var:, cloak: None, pog: None)

  let funcs = [
    build_cloak,
    build_pog,
  ]

  list.fold(funcs, #(flags, []), fn(acc, func) {
    let #(flags, old_add_worker_funcs) = acc

    let #(flags, add_worker_funcs) = func(flags, features)

    old_add_worker_funcs
    |> list.append(add_worker_funcs)
    |> pair.new(flags, _)
  })
}

fn build_cloak(
  flags flags: Flags,
  features features: Features,
) -> #(Flags, List(fn(static_supervisor.Builder) -> static_supervisor.Builder)) {
  use load <- guard.some(features.cloak, #(flags, []))

  let load = fn() { load(flags.env_var) }

  let name = process.new_name("cloak-store")
  let cloak = Cloak(name:, store: cloak_store.get(name:))
  let flags = Flags(..flags, cloak: Some(cloak))

  fn(supervisor) {
    supervisor
    |> static_supervisor.add(cloak_store.supervised(name:, load:))
  }
  |> list.wrap
  |> pair.new(flags, _)
}

fn build_pog(
  flags flags: Flags,
  features features: Features,
) -> #(Flags, List(fn(static_supervisor.Builder) -> static_supervisor.Builder)) {
  use pog <- guard.some(features.pog, #(flags, []))

  let conn_url =
    case pog {
      types.Pog(conn_url:) ->
        conn_url

      types.PogConnUrlEnvVar(name:) -> {
        let assert Ok(conn_url) = flags.env_var.get_string(name) as { "read pog conn url $" <> name}
        conn_url
      }
    }

  let #(pog, add_worker) = connect_to_postgres(conn_url:)

  #(Flags(..flags, pog: Some(pog)), [add_worker])
}

fn connect_to_postgres(
  conn_url conn_url: String,
) -> #(pog.Connection, fn(static_supervisor.Builder) -> static_supervisor.Builder) {
  let name = process.new_name("pog")
  let assert Ok(cfg) = pog.url_config(name, conn_url) as "parse postgres url (`pog.url_config`)"

  let add_worker = fn(supervisor) {
    let worker =
      supervision.worker(fn() {
        let assert Ok(_) as started = pog.start(cfg) as "start postgres (`pog.start`)"
        started
      })

    supervisor
    |> static_supervisor.add(worker)
  }

  #(pog.named_connection(name), add_worker)
}
