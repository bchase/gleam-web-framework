import spec/config.{type Config, type PubSub, init_config, add_pubsub_workers, authenticate}
import spec/user.{type User}
import app/types/spec.{type Spec, Spec}
import spec/websockets
import spec/router

pub fn spec() -> Spec(Config, PubSub, User) {
  Spec(
    app_module_name: "app",
    dot_env_relative_path: ".env",
    secret_key_base_env_var_name: "SECRET_KEY_BASE",
    //
    init_config:,
    add_pubsub_workers:,
    //
    authenticate:,
    //
    websockets_path_prefix: "ws",
    websockets_router: websockets.lustre_server_component_router,
    //
    router: router.handler,
  )
}
