import gleam/option.{type Option, None}
import gleam/erlang/process
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

const spec =
  Spec(
    app_module_name: "app",
    dot_env_relative_path: ".env",
    secret_key_base_env_var_name: "SECRET_KEY_BASE",
    init_config: config.init,
    authenticate:,
    websockets_path_prefix: "ws",
    websockets_router: websockets.router,
    router: router.handler,
  )

pub fn main() -> Nil {
  let assert Ok(_) =
    web.start_supervisor(
      spec:,
      one_for_one_children: [],
    )

  process.sleep_forever()
}
