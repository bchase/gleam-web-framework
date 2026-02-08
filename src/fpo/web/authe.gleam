import gleam/bit_array
import gleam/crypto
import gleam/result
import gleam/option.{Some, None}
import fpo/web/session
import fpo/types.{type Session, Session}
import wisp
import fpo/types/spec.{type Handler}
import fpo/monad/app.{type App, pure, do}
import fpo/generic/guard
import fpo/generic/crypto.{hash_sha256_base64} as _

pub fn sign_in(
  user user: user,
  redirect_to location: String,
  persist_user_token persist_user_token: fn(user, String) -> App(Result(a, Nil), config, pubsub, user),
) -> Result(Handler(config, pubsub, user), Nil) {
  Ok(spec.AppWispSessionCookieHandler(handle: fn(req, session, session_cookie_name) {
    let session = session  |> result.lazy_unwrap(fn() { types.zero_session() })

    use result <- do(set_token(user:, session:, persist_user_token:))

    case result {
      Error(Nil) ->
        wisp.response(500)

      Ok(session) ->
        wisp.response(302)
        |> wisp.set_header("location", location)
        |> session.write(
          req:,
          session:,
          max_age: None,
          session_cookie_name:,
        )
    }
    |> pure
  }))
}

pub fn sign_out(
  delete_user_token delete_user_token: fn(String) -> App(Result(Nil, Nil), config, pubsub, user)
) -> Result(Handler(config, pubsub, user), Nil) {
  Ok(spec.AppWispSessionCookieHandler(handle: fn(req, session, session_cookie_name) {
    let session = session |> result.lazy_unwrap(fn() { types.zero_session() })

    use session <- do(clear_token(session:, delete_user_token:))

    wisp.response(302)
    |> wisp.set_header("location", "/")
    |> session.write(
      req:,
      session:,
      max_age: None,
      session_cookie_name:,
    )
    |> pure
  }))
}

//

fn set_token(
  session session: Session,
  user user: user,
  persist_user_token persist_user_token: fn(user, String) -> App(Result(token, Nil), config, pubsub, user),
) -> App(Result(Session, Nil), config, pubsub, user) {
  let token = crypto.strong_random_bytes(32)
  let hashed_token = hash_sha256_base64(token)
  use result <- do(persist_user_token(user, hashed_token))

  use _token_row <- guard.ok_(result, fn(_) { pure(Error(Nil)) })

  let token_str = bit_array.base64_encode(token, True)

  pure(Ok(Session(..session, user_token: Some(token_str))))
}

fn clear_token(
  session session: Session,
  delete_user_token delete_user_token: fn(String) -> App(Result(Nil, Nil), config, pubsub, user)
) -> App(Session, config, pubsub, user) {
  use token <- guard.some(session.user_token, pure(session))

  let hashed_token =
    token
    |> bit_array.from_string
    |> hash_sha256_base64

  use _deleted <- do(delete_user_token(hashed_token))

  pure(Session(..session, user_token: None))
}
