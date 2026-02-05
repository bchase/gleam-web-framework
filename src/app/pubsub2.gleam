import gleam/option.{type Option, Some, None}
import app/erl
import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/atom
import gleam/erlang/node
import gleam/erlang/process.{type Selector}
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import gleam/string
import group_registry as gr
import app/generic/json.{type Transcoders} as _
//
import gleam/otp/static_supervisor

pub fn add_local_node_only_worker(
  supervisor supervisor: static_supervisor.Builder,
  name name_str: String,
) -> #(static_supervisor.Builder, PubSub(msg)) {
  let #(name_str, name) = pubsub_name(name_str:, suffix: "registry", app_module_name: None)

  let pubsub = PubSub(name_str:, name:, transcoders: None)

  let supervisor =
    supervisor
    |> static_supervisor.add(gr.supervised(name))

  #(supervisor, pubsub)
}

pub fn add_cluster_worker(
  supervisor supervisor: static_supervisor.Builder,
  name name_str: String,
  transcoders transcoders: Transcoders(msg),
  app_module_name app_module_name: String,
) -> #(static_supervisor.Builder, PubSub(msg)) {
  let #(registry_name_str, registry_name) = pubsub_name(name_str:, suffix: "registry", app_module_name: Some(app_module_name))
  let pubsub = PubSub(name_str: registry_name_str, name: registry_name, transcoders: Some(transcoders))

  let #(_, listener_name) = pubsub_name(name_str:, suffix: "cluster_listener", app_module_name: Some(app_module_name))

  let supervisor =
    supervisor
    |> static_supervisor.add(gr.supervised(registry_name))
    |> static_supervisor.add(supervised_cluster_listener(name: listener_name, transcoders:))

  #(supervisor, pubsub)
}

fn pubsub_name(
  name_str name_str: String,
  suffix suffix: String,
  app_module_name app_module_name: Option(String),
) -> #(String, process.Name(msg)) {
  let name_str = name_str <> "_pubsub_" <> suffix

  case app_module_name {
    None -> {
      let name = name_str |> process.new_name
      #(name_str, name)
    }

    Some(app_module_name) -> {
      let name_str = app_module_name <> "_" <> name_str
      let name = name_str |> unsafe_unique_name_from
      #(name_str, name)
    }
  }
}

//

pub opaque type PubSub(msg) {
  PubSub(
    name_str: String,
    name: process.Name(gr.Message(msg)),
    transcoders: Option(Transcoders(msg))
  )
}

pub fn subscribe(
  pubsub pubsub: PubSub(msg),
  channel channel: String,
) -> Selector(msg) {
  pubsub.name
  |> gr.get_registry
  |> gr.join(channel, process.self())
  |> process.select(process.new_selector(), _)
}

// // TODO -- i think `subscribe`, `unsubscribe`, `subscribe` results
// //      -- in double msgs because of double `Selector` usage...
// pub fn unsubscribe(
//   pubsub pubsub: PubSub(msg),
//   channel channel: String,
// ) -> Nil {
//   pubsub.name
//   |> gr.get_registry
//   |> gr.leave(channel, [process.self()])
// }

pub fn broadcast(
  pubsub pubsub: PubSub(msg),
  channel channel: String,
  msg msg: msg,
) -> Nil {
  broadcast_local(pubsub:, channel:, msg:)
  broadcast_to_cluster(pubsub:, channel:, msg:) |> option.unwrap(Nil)
}

fn broadcast_local(
  pubsub pubsub: PubSub(msg),
  channel channel: String,
  msg msg: msg,
) -> Nil {
  pubsub.name
  |> gr.get_registry
  |> gr.members(channel)
  |> list.each(fn(subscriber) {
    subscriber
    |> process.send(msg)
  })
}

fn broadcast_to_cluster(
  pubsub pubsub: PubSub(msg),
  channel channel: String,
  msg msg: msg,
) -> Option(Nil) {
  use transcoders <- option.then(pubsub.transcoders)

  let self = node.self()

  node.visible()
  |> list.each(fn(node) {
    use <- bool.guard(node == self, Nil)

    msg
    |> encode_cluster_msg(pubsub:, channel:, transcoders:)
    |> erl.node_send(msg: _, node:, name: pubsub.name)
  })

  None
}

//

fn encode_cluster_msg(
  msg msg: msg,
  pubsub pubsub: PubSub(msg),
  channel channel: String,
  transcoders transcoders: Transcoders(msg),
) -> Json {
  json.object([
    #("pubsub", pubsub.name_str |> json.string),
    #("channel", channel |> json.string),
    #("msg", msg |> transcoders.encode),
  ])
}

fn decoder_cluster_msg(
  decoder decoder: Decoder(msg),
) -> Decoder(Result(#(PubSub(msg), String, msg), String)) {
  {
    use name_str <- decode.field("name", decode.string)
    use channel <- decode.field("channel", decode.string)
    use msg <- decode.field("msg", decoder)

    case name_from(name_str:) {
      Error(Nil) -> {
        // decode.failure(#(pubsub, channel, msg))
        decode.success(Error("`decoder_cluster_msg` no `Name` for: " <> name_str))
      }

      Ok(name) -> {
        let pubsub = PubSub(name_str:, name:, transcoders: None)

        decode.success(Ok(#(pubsub, channel, msg)))
      }
    }
  }
}

fn unsafe_name_from(
  name_str str: String,
) -> process.Name(msg) {
  str
  |> atom.create
  |> erl.unsafe_cast
}

fn name_from(
  name_str str: String,
) -> Result(process.Name(msg), Nil) {
  let name = unsafe_name_from(str)

  name
  |> process.named
  |> result.replace(name)
}

fn unsafe_unique_name_from(
  name_str name_str: String,
) -> process.Name(msg) {
  case atom.get(name_str) {
    Ok(_atom) ->
      panic as { "`unsafe_unique_name_from` atom already exists: " <> name_str }

    Error(Nil) -> {
      // let assert Ok(name) = unsafe_name_from(name_str:)
      // name
      unsafe_name_from(name_str:)
    }
  }
}

fn supervised_cluster_listener(
  // name name: process.Name(Result(msg, #(Dynamic, List(DecodeError)))),
  name name: process.Name(Dynamic),
  transcoders transcoders: Transcoders(msg),
  // broadcast broadcast:
) -> ChildSpecification(Nil) {
  let decoder = transcoders.decoder()

  supervision.worker(fn() {
    actor.new_with_initialiser(100, fn(subject) {
      actor.initialised(Nil)
      |> actor.selecting({
        process.new_selector()
        |> process.select(subject)
        // |> process.select_other(fn(dyn) {
        //   dyn
        //   |> decode.run(transcoders.decoder)
        //   |> result.map_error(pair.new(dyn, _))
        // })
      })
      |> Ok
    })
    |> actor.on_message(fn(state, dyn_msg) {
      let result =
          dyn_msg
          |> decode.run(decode.string)
          |> result.map(json.parse(_, decoder_cluster_msg(decoder)))

      case result {
        Ok(Ok(Ok(#(pubsub, channel, msg)))) -> {
          broadcast_local(pubsub:, channel:, msg:)

          actor.continue(state)
        }

        Ok(Ok(Error(errs))) -> {
          log_err(name:, dyn_msg:, errs:)

          actor.continue(state)
        }

        Ok(Error(errs)) -> {
          log_err(name:, dyn_msg:, errs:)

          actor.continue(state)
        }

        Error(errs) -> {
          log_err(name:, dyn_msg:, errs:)

          actor.continue(state)
        }
      }
    })
    |> actor.named(name)
    |> actor.start
  })
}

fn log_err(
  name name: process.Name(msg),
  dyn_msg dyn_msg: Dynamic,
  errs errs: a,
) -> Nil {
  [
    "ERR `supervised_cluster_listener` " <> name |> string.inspect,
    "  PAYLOAD: " <> dyn_msg |> string.inspect,
    "  ERRS: " <> errs |> string.inspect,
  ]
  |> string.join("\n")
  |> io.println_error
}

// fn static_name(
//   name_str name_str: String,
// ) -> process.Name(msg) {
// }
