import gleam/string
import gleam/option.{type Option, None}
import gleam/erlang/process
import gleam/otp/static_supervisor
import app/config.{type Config}
import app/types.{type Session}
import app/types/spec.{Spec}
import app/websockets
import app/router
import app/web

type User {
  User
}
fn authenticate(
  session _session: Session,
  cfg _cfg: Config,
) -> Option(User) {
  None
}

pub fn main() -> Nil {
  let assert Ok(_) =
    Spec(
      app_module_name: "app",
      dot_env_relative_path: ".env",
      secret_key_base_env_var_name: "SECRET_KEY_BASE",
      init_config: config.init,
      authenticate:,
      websockets_path_prefix: "ws",
      websockets_router: websockets.lustre_server_component_router,
      router: router.handler,
    )
    |> web.supervised
    |> static_supervisor.start

  process.sleep_forever()
}
