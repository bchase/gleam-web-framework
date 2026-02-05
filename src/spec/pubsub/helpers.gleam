import app/pubsub
import spec/config
import spec/pubsub.{type TextMsg} as _

pub fn text(pubsub: config.PubSub) -> pubsub.PubSub(TextMsg) { pubsub.text }
