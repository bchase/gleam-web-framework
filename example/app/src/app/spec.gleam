import gleam/option.{Some}
import app/config.{type Config, type PubSub, add_pubsub_workers, authenticate}
import app/user.{type User}
import fpo/types.{type EnvVar, Features}
import fpo/types/spec.{type Spec, Spec}
import app/web/websockets
import app/web/router
import cloak_wrapper/aes/gcm as aes_gcm

const cloak_key_env_var_name = "CLOAK_KEY"

pub fn spec() -> Spec(Config, PubSub, User) {
  Spec(
    app_module_name: "fpo",
    session_cookie_name: "fpo",
    dot_env_relative_path: ".env",
    secret_key_base_env_var_name: "SECRET_KEY_BASE",
    //
    config: spec.Config(
      features: Features(cloak: Some(fn(env_var) { load_cloak_config(env_var) })),
      init: config.init,
    ),
    add_pubsub_workers:,
    authenticate:,
    //
    websockets_path_prefix: "ws",
    websockets_router: websockets.lustre_server_component_router,
    //
    router: router.handler,
  )
}

fn load_cloak_config(
  env_var env_var: EnvVar,
) -> aes_gcm.Config {
  let key =
    case env_var.get_string(cloak_key_env_var_name) {
      Error(_) -> panic as { "$" <> cloak_key_env_var_name <> " env var not set" }
      Ok(key) -> key
    }

  aes_gcm.config(
    key:,
    tag: "AES.GCM.V1",
    iv_length: 12,
  )
}
