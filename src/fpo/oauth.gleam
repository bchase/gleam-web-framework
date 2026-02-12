import gleam/dynamic/decode.{type Decoder}
import gleam/hackney
import gleam/http/request.{type Request}
import gleam/io
import gleam/json.{type Json}
import gleam/string
import gleam/uri.{type Uri}
import glow_auth.{type Client, Client}
import glow_auth/access_token.{type AccessToken}
import glow_auth/authorize_uri
import glow_auth/token_request
import glow_auth/uri/uri_builder.{type UriAppendage, RelativePath}
import fpo/generic/json.{Transcoders} as _
import fpo/oauth/state.{type State}
import fpo/monad/app.{type App, pure, do}
//
import gleam/result
import birl/duration
import gleam/bool
import gleam/time/timestamp.{type Timestamp}
import gleam/option.{type Option, Some}
import fpo/oauth/tokens.{type Unencrypted, type Encrypted, type Tokens}
import fpo/types/err
import fpo/generic/guard
import fpo/cloak.{type Cloak}
import birl
import fpo/generic/birl as fpo_birl
import gleam/order

pub type Config(provider) {
  Config(
    provider: String,
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

pub type Refreshed(provider) {
  Refreshed(
    tokens: Tokens(Encrypted),
  )
}

pub fn build_oauth_config(
  provider provider: String,
  authz_base_uri authz_base_uri: String,
  authz_endpoint_path authz_endpoint_path: String,
  token_base_uri token_base_uri: String,
  token_endpoint_path token_endpoint_path: String,
  redirect_uri redirect_uri: String,
  client_id client_id: String,
  client_secret client_secret: String,
  scopes scopes: List(String),
  scopes_separator scopes_separator: String,
) -> Config(provider) {
  let assert Ok(authz_site) = uri.parse(authz_base_uri)
  let authz_client = Client(client_id, client_secret, authz_site)
  let authz_path = RelativePath(authz_endpoint_path)

  let assert Ok(token_site) = uri.parse(token_base_uri)
  let token_client = Client(client_id, client_secret, token_site)
  let token_path = RelativePath(token_endpoint_path)

  let assert Ok(redirect_uri) = uri.parse(redirect_uri)

  Config(
    provider:,
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
  cfg cfg: Config(provider),
  scopes scopes: List(String),
  scopes_separator scopes_separator: String,
) -> App(Uri, config, pubsub, user, err) {
  use state <- app.do(state.new_signed())

  cfg.authz_client
  |> authorize_uri.build(cfg.authz_path, cfg.redirect_uri)
  |> authorize_uri.set_scope(scopes |> string.join(scopes_separator))
  |> authorize_uri.set_state(state)
  |> authorize_uri.to_code_authorization_uri
  |> app.pure
}

pub fn fetch_access_token(
  cfg cfg: Config(provider),
  code code: String,
) -> Result(AccessToken, Nil) {
  cfg.token_client
  |> token_request.authorization_code(
    cfg.token_path,
    code,
    cfg.redirect_uri,
  )
  |> fetch_token
}

pub fn fetch_refresh_token(
  oauth_cfg: Config(provider),
  refresh_token: String,
) -> Result(AccessToken, Nil) {
  let refresh_token =
    refresh_token
    |> uri.percent_encode
    // |> bit_array.from_string
    // |> bit_array.base64_encode(True)

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

pub fn refresh(
  cfg cfg: fn(config) -> Config(provider),
  cloak cloak: fn(config) -> Cloak,
  refresh refresh: Option(fn(Config(provider), String) -> Result(Tokens(Unencrypted), Nil)),
  to_tokens to_tokens: fn(oauth) -> Tokens(Encrypted),
  get_oauth get_oauth: fn(user, String) -> App(oauth, config, pubsub, user, err),
  update_oauth update_oauth: fn(oauth, Tokens(Encrypted)) -> App(oauth, config, pubsub, user, err),
) -> App(Refreshed(provider), config, pubsub, user, err) {
  use user <- do(app.user())

  use ctx <- do(app.ctx())
  let cfg = cfg(ctx.cfg)

  use oauth <- do(get_oauth(user, cfg.provider))

  let tokens = oauth |> to_tokens

  use _has_refresh_token <- guard.some_(
    tokens.refresh_token,
    fn() { pure(Refreshed(tokens)) },
  )

  let expires_soon =
    tokens.expires_at(tokens)
    |> option.map(expires_within_next_hour)
    |> fn(x) { x == Some(True) }

  use <- bool.lazy_guard(!expires_soon, fn() {
    pure(Refreshed(tokens))
  })

  let fetch =
    refresh
    |> option.lazy_unwrap(fn() {
      fn(cfg, str) {
        str
        |> fetch_refresh_token(cfg, _)
        |> result.map(tokens.from)
      }
    })

  use tokens.Tokens(refresh_token:, ..) <- app.do_ok(
    tokens.decrypt(tokens:, store: cloak),
    fn(_) { err.Err("oauth refresh failed to decrypt") },
  )

  use refresh_token <- guard.some_(
    refresh_token,
    fn() { pure(Refreshed(tokens)) },
  )

  use tokens <- guard.ok_(
    refresh_token.token
    |> fetch(cfg, _),
    fn(_) { app.fail(err.Err("oauth refresh fetch (http) failed")) },
  )

  use tokens <- app.do_ok(
    tokens.encrypt(tokens:, store: cloak),
    fn(_) { err.Err("oauth refresh failed to encrypt") },
  )

  use oauth <- do(update_oauth(oauth, tokens))

  let tokens = oauth |> to_tokens

  pure(Refreshed(tokens))
}

fn expires_within_next_hour(
  ts ts: Timestamp,
) -> Bool {
  let expiry = ts |> fpo_birl.from_timestamp

  let one_hour_from_now =
    birl.utc_now()
    |> birl.add(duration.hours(1))

  birl.compare(one_hour_from_now, expiry) == order.Gt
}
