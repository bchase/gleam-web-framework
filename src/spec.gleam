import app/oauth
import app/oauth/oura
import gleam/option.{type Option, None}
import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}
import gleam/otp/static_supervisor
import app/pubsub
import app/config.{type Config, type PubSub, type User, init_config, add_pubsub_workers, authenticate}
import app/types.{type Session}
import app/types/spec.{type Spec, Spec}
import app/websockets
import app/router

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
