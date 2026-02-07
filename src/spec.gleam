import gleam/option.{Some}
import spec/config.{type Config, type PubSub, add_pubsub_workers, authenticate}
import spec/user.{type User}
import app/types.{Features}
import app/types/spec.{type Spec, Spec}
import spec/websockets
import spec/router
import cloak_wrapper/aes/gcm as aes_gcm
import cloak_wrapper/crypto/key

pub fn spec() -> Spec(Config, PubSub, User) {
  Spec(
    app_module_name: "app",
    dot_env_relative_path: ".env",
    secret_key_base_env_var_name: "SECRET_KEY_BASE",
    //
    config: spec.Config(
      features: Features(cloak: Some(load_cloak_config)),
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

fn load_cloak_config() -> aes_gcm.Config {
  aes_gcm.config(
    key: key.gen_base64(32),
    tag: "AES.GCM.V1",
    iv_length: 12,
  )
}
