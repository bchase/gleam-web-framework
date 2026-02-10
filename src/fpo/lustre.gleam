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
      case app.run(app, ctx) {
        Error(err) -> dispatch(to_err(err))
        Ok(x) -> dispatch(to_msg(x))
      }
    })

    Nil
  })
  |> pure
}
