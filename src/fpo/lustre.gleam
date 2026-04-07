import gleam/list
import gleam/pair
import gleam/erlang/process
import fpo/monad/app.{type App, pure, do}
import fpo/types/err
// import fpo/types.{type Context}
import lustre/effect.{type Effect}

pub fn component(
  model model: model,
  effs effs: List(Effect(msg)),
) -> App(#(model, Effect(msg)), config, pubsub, user, err) {
  pure(#(model, effect.batch(effs)))
}

pub fn continue(
  model model: model,
  effs effs: List(App(Effect(msg), config, pubsub, user, err)),
) -> App(#(model, Effect(msg)), config, pubsub, user, err) {
  use effs <- do(app.sequence(effs))

  pure(#(model, effect.batch(effs)))
}

pub fn eff(
  app app: App(t, config, pubsub, user, err),
  to_msg to_msg: fn(t) -> msg,
  to_err to_err: fn(err.Err(err)) -> msg,
) -> App(Effect(msg), config, pubsub, user, err) {
  use ctx <- do(app.ctx())

  effect.from(fn(dispatch) {
    process.spawn_unlinked(fn() {
      case app.run(app, ctx, Nil) {
        Error(err) -> dispatch(to_err(err))
        Ok(x) -> dispatch(to_msg(x))
      }
    })

    Nil
  })
  |> pure
}

pub fn map(
  app app: App(#(inner_model, Effect(inner_msg)), config, pubsub, user, err),
  model model: fn(inner_model) -> model,
  msg msg: #(fn(inner_msg) -> inner_wrapped_msg, fn(inner_wrapped_msg) -> msg),
) -> App(#(model, Effect(msg)), config, pubsub, user, err) {
  let #(inner_msg, msg) = msg

  app
  |> app.map(pair.map_first(_, model))
  |> app.map(pair.map_second(_, effect.map(_, inner_msg)))
  |> app.map(pair.map_second(_, effect.map(_, msg)))
}

pub fn init(
  model model: model,
  msgs msgs: List(msg),
  effs effs: List(App(Effect(msg), config, pubsub, user, err)),
) -> App(#(model, Effect(msg)), config, pubsub, user, err) {
  let msgs = msgs |> list.map(send) |> list.map(pure)
  let effs = [msgs, effs] |> list.flatten
  model |> continue(effs)
}

fn send(
  msg msg: msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    dispatch(msg)
    Nil
  })
}
