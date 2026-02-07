import cloak_wrapper/store.{type Msg as CloakStoreMsg} as cloak
import gleam/erlang/process.{type Name}

pub type Cloak {
  Cloak(
    name: Name(CloakStoreMsg),
    store: cloak.Store,
  )
}
