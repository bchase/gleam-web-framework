import fpo/cloak
import gleam/result
import birl
import gleam/order
import gleam/option.{type Option}
import gleam/time/timestamp as ts
import glow_auth/access_token as glow_auth
import fpo/monad/app.{type App, pure}
import cloak_wrapper/store
import fpo/generic/prelude
import fpo/generic/birl as fpo_birl

pub type Unencrypted
pub type Encrypted

pub opaque type Tokens(encryption) {
  Tokens(
    access_token: Token(encryption),
    access_token_expires_at: Option(ts.Timestamp),
    refresh_token: Option(Token(encryption)),
  )
}

pub opaque type Token(encryption) {
  Token(token: String)
}

pub fn from(
  oauth oauth: glow_auth.AccessToken,
) -> Tokens(Unencrypted) {
  Tokens(
    access_token: oauth.access_token |> Token,
    access_token_expires_at: oauth.expires_at |> option.map(ts.from_unix_seconds),
    refresh_token: oauth.refresh_token |> option.map(Token)
  )
}

pub fn expired(
  tokens tokens: Tokens(encryption),
) -> Option(Bool) {
  use expires_at <- option.map(tokens.access_token_expires_at)

  expires_at
  |> fpo_birl.from_timestamp
  |> birl.compare(birl.utc_now())
  |> fn(comp) { comp == order.Lt }
}

pub fn expires_at(
  tokens tokens: Tokens(encryption),
) -> Option(ts.Timestamp) {
  tokens.access_token_expires_at
}

pub fn encrypted_access_token(
  tokens tokens: Tokens(encryption),
) -> Token(encryption) {
  tokens.access_token
}

pub fn encrypted_refresh_token(
  tokens tokens: Tokens(encryption),
) -> Option(Token(encryption)) {
  tokens.refresh_token
}

pub type EncryptionErr(id) {
  DecryptFailure
  EncryptFailure
}

pub fn encrypt(
  tokens tokens: Tokens(Unencrypted),
  store store: fn(config) -> cloak.Cloak,
) -> App(Result(Tokens(Encrypted), EncryptionErr(id)), config, pubsub, user, err) {
  encrypt_func(store:) |> run(func: _, tokens:, err: EncryptFailure)
}

pub fn decrypt(
  tokens tokens: Tokens(Encrypted),
  store store: fn(config) -> cloak.Cloak,
) -> App(Result(Tokens(Unencrypted), EncryptionErr(id)), config, pubsub, user, err) {
  decrypt_func(store:) |> run(func: _, tokens:, err: DecryptFailure)
}

pub opaque type EncryptionFunc(return) {
  EncryptionFunc(
    run: fn(String) -> Result(Token(return), Nil)
  )
}

fn encrypt_func(
  store store: fn(config) -> cloak.Cloak,
) -> App(EncryptionFunc(Encrypted), config, pubsub, user, err) {
  store.encrypt |> encryption_func(store:)
}


fn decrypt_func(
  store store: fn(config) -> cloak.Cloak,
) -> App(EncryptionFunc(Unencrypted), config, pubsub, user, err) {
  store.decrypt |> encryption_func(store:)
}

fn encryption_func(
  f f: fn(store.Store, String) -> Result(String, Nil),
  store store: fn(config) -> cloak.Cloak,
) -> App(EncryptionFunc(encryption), config, pubsub, user, err) {
  use ctx <- app.map(app.ctx())
  let store = store(ctx.cfg).store

  fn(ciphertext) {
    f(store, ciphertext)
    |> result.map(Token)
  }
  |> EncryptionFunc
}

fn run(
  tokens tokens: Tokens(from),
  func func: App(EncryptionFunc(to), config, pubsub, user, err),
  err err: EncryptionErr(id),
) -> App(Result(Tokens(to), EncryptionErr(id)), config, pubsub, user, err) {
  use func <- app.do(func)

  let Tokens(access_token:, refresh_token:, access_token_expires_at:) = tokens

  use access_token <- app.ok__({
    func.run(access_token.token)
  }, err)

  use refresh_token <- app.ok__({
    refresh_token
    |> option.map(fn(token) { token.token })
    |> option.map(func.run)
    |> prelude.option_result_to_result_option
  }, err)

  pure(Ok(Tokens(access_token:, access_token_expires_at:, refresh_token:)))
}
