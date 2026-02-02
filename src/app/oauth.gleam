import gleam/json.{type Json}
import gleam/string
import gleam/hackney
import gleam/http/request.{type Request}
import gleam/io
import gleam/uri.{type Uri}
import glow_auth.{type Client, Client}
import glow_auth/access_token.{type AccessToken}
import glow_auth/authorize_uri
import glow_auth/token_request
import glow_auth/uri/uri_builder.{type UriAppendage, RelativePath}

pub type Config {
  Config(
    client_id: String,
    client_secret: String,
    authz_client: Client(String),
    authz_path: UriAppendage,
    token_client: Client(String),
    token_path: UriAppendage,
    redirect_uri: Uri,
    scopes: List(String),
    scopes_separator: String,
  )
}

pub fn build_oauth_config(
  authz_base_uri authz_base_uri: String,
  authz_endpoint_path authz_endpoint_path: String,
  token_base_uri token_base_uri: String,
  token_endpoint_path token_endpoint_path: String,
  redirect_uri redirect_uri: String,
  client_id client_id: String,
  client_secret client_secret: String,
) -> Config {
  let assert Ok(authz_site) = uri.parse(authz_base_uri)
  let authz_client = Client(client_id, client_secret, authz_site)
  let authz_path = RelativePath(authz_endpoint_path)

  let assert Ok(token_site) = uri.parse(token_base_uri)
  let token_client = Client(client_id, client_secret, token_site)
  let token_path = RelativePath(token_endpoint_path)

  let assert Ok(redirect_uri) = uri.parse(redirect_uri)

  let scopes = []
  let scopes_separator = " "

  Config(
    client_id:,
    client_secret:,
    authz_client:,
    authz_path:,
    token_client:,
    token_path:,
    redirect_uri:,
    scopes:,
    scopes_separator:,
  )
}

pub fn authorize_redirect_uri(
  cfg cfg: Config,
  scopes scopes: List(String),
  scopes_separator scopes_separator: String,
  state state: Json,
) -> Uri {
  let scope =
    scopes
    |> string.join(scopes_separator)
    |> uri.percent_encode

  let state =
    state
    |> todo
    |> uri.percent_encode

  cfg.authz_client
  |> authorize_uri.build(cfg.authz_path, cfg.redirect_uri)
  |> authorize_uri.set_scope(scope)
  |> authorize_uri.set_state(state)
  |> authorize_uri.to_code_authorization_uri
}

pub fn fetch_access_token(
  oauth_cfg: Config,
  code: String,
) -> Result(AccessToken, Nil) {
  oauth_cfg.token_client
  |> token_request.authorization_code(
    oauth_cfg.token_path,
    code,
    oauth_cfg.redirect_uri,
  )
  |> fetch_token
}

pub fn fetch_refresh_token(
  oauth_cfg: Config,
  refresh_token: String,
) -> Result(AccessToken, Nil) {
  oauth_cfg.token_client
  |> token_request.refresh(oauth_cfg.token_path, refresh_token)
  |> fetch_token
}

pub fn fetch_token(req: Request(String)) -> Result(AccessToken, Nil) {
  case hackney.send(req) {
    Error(http_err) -> {
      io.println_error(http_err |> string.inspect)
      Error(Nil)
    }

    Ok(resp) ->
      case access_token.decode_token_from_response(resp.body) {
        Error(decode_err) -> {
          io.println_error(decode_err |> string.inspect)
          Error(Nil)
        }

        Ok(token) -> Ok(token)
      }
  }
}

//


