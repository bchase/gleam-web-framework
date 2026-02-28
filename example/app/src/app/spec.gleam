import gleam/option.{Some}
import app/config.{add_pubsub_workers}
import app/user.{type User, authenticate}
import fpo/types.{type EnvVar, Features}
import fpo/types/spec.{type Spec, Spec}
import fpo/lustre/server_component as lsc
import app/web/websockets
import app/web/router
import cloak_wrapper/aes/gcm as aes_gcm
import app/types.{type Config, type PubSub, type Err} as _
//
import app/web/components/counter_app

pub fn spec() -> Spec(Config, PubSub, User, Err) {
  panic as "`register_server_components` not working"

  let assert Ok(server_components) =
    register_server_components() as "registered server components with unique routes"

  Spec(
    app_module_name: "app",
    session_cookie_name: "app",
    dot_env_relative_path: ".env",
    secret_key_base_env_var_name: "SECRET_KEY_BASE",
    //
    config: spec.Config(
      features: Features(
        fpo_path_prefix: "_",
        cloak: Some(load_cloak_config),
        pog: Some(types.PogConnUrlEnvVar(name: "PG_URL")),
        set_user_client_info: Some(types.SetUserClientInfo(
          path_prefix: "_fpo",
          browser_js_path: "/static/js/fpo-gleam-browser.js",
        )),
      ),
      init: config.init,
    ),
    add_pubsub_workers:,
    authenticate:,
    //
    websockets_path_prefix: "ws",
    websockets_router: websockets.lustre_server_component_router,
    //
    router: router.handler,
    //
    server_components:,
  )
}

fn register_server_components() {
  lsc.new()
  |> lsc.register_many([
    counter_app.server_component(),
  ])
}

const cloak_key_env_var_name = "CLOAK_KEY"

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
