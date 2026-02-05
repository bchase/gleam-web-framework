import app/monad/app
import gleam/erlang/process
import app/pubsub2 as pubsub
import app/config

fn text(pubsub: config.PubSub) -> pubsub.PubSub(config.TextMsg) { pubsub.text }

pub fn subscribe_text(
  to to: String,
  wrap wrap: fn(config.TextMsg) -> msg
) -> app.App(process.Selector(msg), config, config.PubSub, user) {
  app.subscribe(wrap:, to:, in: text)
}

pub fn broadcast_text(
  to to: String,
  msg msg: config.TextMsg,
  cont cont: fn() -> app.App(t, config, config.PubSub, user)
) -> app.App(t, config, config.PubSub, user) {
  app.broadcast(to:, msg:, cont:, in: text)
}
