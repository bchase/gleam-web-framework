import gleam/option.{type Option, None}
import gleam/erlang/process
import app/types.{type Session, Spec}
import app/config.{type Config}
import app/websockets
import app/router
import app/web

// TODO mv
type User {
  User
}
fn authenticate(
  session session: Session,
  cfg _cfg: Config,
) -> Option(User) {
  None
}
// TODO mv

const spec =
  Spec(
    dot_env_relative_path: ".env",
    secret_key_base_env_var_name: "SECRET_KEY_BASE",
    init_config: config.init,
    authenticate:,
    mist_websockets_handler: websockets.handler,
    wisp_handler: router.handler,
  )

pub fn main() -> Nil {
  let assert Ok(_) =
    web.start_supervisor(
      spec:,
      one_for_one_children: [],
    )

  process.sleep_forever()
}
