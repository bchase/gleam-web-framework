import app/monad/app.{type App, pure}
// import app/types.{type Context}
import lustre/effect.{type Effect}

pub fn component(
  model model: model,
  effs effs: List(Effect(msg)),
) -> App(#(model, Effect(msg)), config, user) {
  pure(#(model, effect.batch(effs)))
}

pub fn continue(
  model model: model,
  effs effs: List(Effect(msg)),
) -> App(#(model, Effect(msg)), config, user) {
  pure(#(model, effect.batch(effs)))
}
