import app/oauth
import dot_env/env
// import app/oauth/refresh.{build_refreshed_client}

const oura_authz_base_uri = "https://cloud.ouraring.com"
const oura_authz_endpoint_path = "oauth/authorize"

const oura_token_base_uri = "https://api.ouraring.com"
const oura_token_endpoint_path = "oauth/token"

pub fn build_config() -> oauth.Config {
  let assert Ok(oura_client_id) = env.get_string("OURA_CLIENT_ID")
  let assert Ok(oura_client_secret) = env.get_string("OURA_CLIENT_SECRET")
  let assert Ok(oura_redirect_uri) = env.get_string("OURA_REDIRECT_URL")

  build_oauth_config_(
    client_id: oura_client_id,
    client_secret: oura_client_secret,
    redirect_uri: oura_redirect_uri,
  )
}

fn build_oauth_config_(
  client_id client_id: String,
  client_secret client_secret: String,
  redirect_uri oura_redirect_uri: String,
) -> oauth.Config {
  oauth.build_oauth_config(
    authz_base_uri: oura_authz_base_uri,
    authz_endpoint_path: oura_authz_endpoint_path,
    token_base_uri: oura_token_base_uri,
    token_endpoint_path: oura_token_endpoint_path,
    redirect_uri: oura_redirect_uri,
    client_id: client_id,
    client_secret: client_secret,
  )
}

// pub fn build_refreshed_oura_client(
//   cfg: Config,
//   authe_id: Uuid,
// ) -> Result(oura.Client, Nil) {
//   build_refreshed_client(
//     cfg,
//     authe_id,
//     fn(cfg) { cfg.oura_oauth },
//     oura.Client(token: _),
//     None,
//   )
// }
