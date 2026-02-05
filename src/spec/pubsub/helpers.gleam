import app/monad/app
import gleam/erlang/process
import app/pubsub
import spec/config
import spec/pubsub.{type TextMsg} as _

fn text(pubsub: config.PubSub) -> pubsub.PubSub(TextMsg) { pubsub.text }

pub fn subscribe_text(
  to to: String,
  wrap wrap: fn(TextMsg) -> msg
) -> app.App(process.Selector(msg), config, config.PubSub, user) {
  app.subscribe(wrap:, to:, in: text)
}

pub fn broadcast_text(
  to to: String,
  msg msg: TextMsg,
  cont cont: fn() -> app.App(t, config, config.PubSub, user)
) -> app.App(t, config, config.PubSub, user) {
  app.broadcast(to:, msg:, cont:, in: text)
}
