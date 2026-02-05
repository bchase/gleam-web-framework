import app/monad/app.{type App, pure, do}
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
