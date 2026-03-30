import fpo/cloak.{type Cloak}
import sqlight
import pog
import fpo/pubsub
import app/pubsub.{type TextMsg} as _
import app/types/err
import api

pub type Err = err.Err

pub type Config {
  Config(
    cloak: Cloak,
    sqlite_conn: sqlight.Connection,
    postgres_conn: pog.Connection,
  )
}

pub type PubSub {
  PubSub(
    text: pubsub.PubSub(TextMsg),
    items: pubsub.PubSub(api.Record(api.Item)),
  )
}

