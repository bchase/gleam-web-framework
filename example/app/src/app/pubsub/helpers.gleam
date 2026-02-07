import fpo/pubsub
import app/pubsub.{type TextMsg} as _
import app/types.{type PubSub}

pub fn text(pubsub: PubSub) -> pubsub.PubSub(TextMsg) { pubsub.text }
