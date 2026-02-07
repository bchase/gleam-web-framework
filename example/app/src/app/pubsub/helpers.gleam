import fpo/pubsub
import app/config
import app/pubsub.{type TextMsg} as _

pub fn text(pubsub: config.PubSub) -> pubsub.PubSub(TextMsg) { pubsub.text }
