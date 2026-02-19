import gleam/option.{type Option, Some, None}
import fpo/generic/guard
import gleam/string
import glow_auth/access_token.{type AccessToken}
import fpo/oauth
import gleam/list
import wisp
import fpo/oauth/state
import fpo/monad/app.{type App}
import fpo/oauth/tokens.{type Tokens, type Unencrypted}

pub fn verify_state_then_fetch_tokens(
  req req: wisp.Request,
  cfg cfg: oauth.Config(provider),
) -> App(Result(Tokens(Unencrypted), RespErr), config, pubsub, user, err) {
  let params = req |> wisp.get_query
  let get = list.key_find(params, _)

  use state <- app.ok__(get("state"), NoState)

  use state.State(..) <- app.do__(
    state.verify(state),
    InvalidState,
  )

  use code <- app.ok__(get("code"), NoCode)

  use oauth <- app.ok__(
    oauth.fetch_access_token(cfg, code),
    InvalidCode,
  )

  let tokens = tokens.from(oauth:, cfg:)

  // makochannnnn
  app.pure(Ok(tokens))
}

// fn scopes(
//   oauth oauth: AccessToken,
//   cfg cfg: oauth.Config(provider),
// ) -> List(String) {
//   use scope <- guard.some(oauth.scope, [])
//   scope |> string.split(cfg.scopes_separator)
// }

pub type RespErr {
  NoState
  InvalidState
  NoCode
  InvalidCode
}

pub fn err_code(
  err err: RespErr,
) -> String {
  case err {
    NoState -> "NoState"
    InvalidState -> "InvalidState"
    NoCode -> "NoCode"
    InvalidCode -> "InvalidCode"
    // MAKE SURE ANYTHING ADDED HERE IS DISPLAYABLE TO USER
  }
}
