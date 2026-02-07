import gleam/erlang/process
import gleam/option.{Some, None}
import gleam/otp/static_supervisor
import app/types.{type Features, type Flags, Flags, type EnvVar}
import cloak_wrapper/store as cloak_store
import app/cloak.{Cloak}

pub fn build(
  features features: Features,
  env_var env_var: EnvVar
) -> #(List(fn(static_supervisor.Builder) -> static_supervisor.Builder), Flags) {
  case features.cloak {
    None -> {
      #([], Flags(cloak: None))
    }

    Some(load) -> {
      let load = fn() { load(env_var) }

      let name = process.new_name("cloak-store")
      let cloak = Cloak(name:, store: cloak_store.get(name:))
      let flags = Flags(cloak: Some(cloak))

      let add_worker_func =
        fn(supervisor) {
          supervisor
          |> static_supervisor.add(cloak_store.supervised(name:, load:))
        }

      #([add_worker_func], flags)
    }
  }
}
