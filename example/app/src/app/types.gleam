import fpo/cloak.{type Cloak}
import sqlight
import pog
import fpo/pubsub
import app/pubsub.{type TextMsg} as _
import app/types/err
import bravo/uset.{}
import api
import api/generic.{type Record}
import api/id.{type Id}

pub type Err = err.Err

pub type Config {
  Config(
    cloak: Cloak,
    sqlite_conn: sqlight.Connection,
    postgres_conn: pog.Connection,
    items: uset.USet(Id(api.Item), Record(api.Item))
  )
}

pub type PubSub {
  PubSub(
    text: pubsub.PubSub(TextMsg),
    items: pubsub.PubSub(api.Record(api.Item)),
  )
}

