import gleam/uri.{type Uri}
import glow_auth.{type Client}
import glow_auth/uri/uri_builder.{type UriAppendage}

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
