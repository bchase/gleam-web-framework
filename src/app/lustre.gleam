import gleam/erlang/process
import app/monad/app.{type App, pure, do}
import app/types/err
// import app/types.{type Context}
import lustre/effect.{type Effect}

pub fn component(
  model model: model,
  effs effs: List(Effect(msg)),
) -> App(#(model, Effect(msg)), config, pubsub, user) {
  pure(#(model, effect.batch(effs)))
}

pub fn continue(
  model model: model,
  effs effs: List(App(Effect(msg), config, pubsub, user)),
) -> App(#(model, Effect(msg)), config, pubsub, user) {
  use effs <- do(app.sequence(effs))

  pure(#(model, effect.batch(effs)))
}

pub fn eff(
  app app: App(t, config, pubsub, user),
  to_msg to_msg: fn(t) -> msg,
  to_err to_err: fn(err.Err) -> msg,
) -> App(Effect(msg), config, pubsub, user) {
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
