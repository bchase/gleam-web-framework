import fpo/types/err
import gleam/result
import fpo/cloak.{type Cloak} as _
import fpo/monad/app.{type App, pure, do}
import fpo/http.{type Req, type Resp} as fhttp
import fpo/oauth/tokens.{type EncryptedToken}
import cloak_wrapper/store as cloak

pub fn send(
  req req: Req(t, metadata),
  cloak cloak: fn(config) -> Cloak,
) -> App(t, config, pubsub, user, err) {
  send_(req:, cloak:, err: err.HttpReqErr)
}

pub fn send_(
  req req: Req(t, metadata),
  cloak cloak: fn(config) -> Cloak,
  err to_err: fn(fhttp.Err) -> err.Err(err),
) -> App(t, config, pubsub, user, err) {
  use resp <- do(send_resp_(req:, cloak:, err: to_err))
  pure(resp.data)
}

//

pub fn send_resp(
  req req: Req(t, metadata),
  cloak cloak: fn(config) -> Cloak,
) -> App(Resp(t, metadata), config, pubsub, user, err) {
  send_resp_(req:, cloak:, err: err.HttpReqErr)
}

pub fn send_resp_(
  req req: Req(t, metadata),
  cloak cloak: fn(config) -> Cloak,
  err to_err: fn(fhttp.Err) -> err.Err(err),
) -> App(Resp(t, metadata), config, pubsub, user, err) {
  use result <- do(send_result_resp(req:, cloak:))

  result
  |> result.map_error(to_err)
  |> app.from_result
}

//

pub fn send_result_resp(
  req req: Req(t, metadata),
  cloak cloak: fn(config) -> Cloak,
) -> App(Result(Resp(t, metadata), fhttp.Err), config, pubsub, user, err) {
  use ctx <- do(app.ctx())
  let store = cloak(ctx.cfg).store

  let decrypt =
    fn(token: EncryptedToken) {
      cloak.decrypt(store:, ciphertext: token.token)
      |> result.map(tokens.Token)
    }

  pure(fhttp.send(req:, decrypt:))
}
