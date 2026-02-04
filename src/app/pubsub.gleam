import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/json.{type Json}
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import group_registry as gr

pub type Spec(msg) {
  Spec(
    init: fn() -> PubSubs,
    add_workers: fn(static_supervisor.Builder, PubSubs) -> static_supervisor.Builder,
    decode_msg: fn() -> Decoder(msg),
  )
}

//

pub const spec = Spec(init:, add_workers:, decode_msg: decoder_unified_msg)

pub type PubSubs {
  PubSubs(
    simple: PubSub(SimpleMsg, UnifiedMsg),
  )
}

pub type SimpleMsg {
  //$ derive json encode decode
  SimpleMsg(text: String)
}

pub type UnifiedMsg {
  //$ derive json encode decode
  WrappedSimpleMsg(msg: SimpleMsg)
}

pub fn init() -> PubSubs {
  PubSubs(
    simple: "simple-pubsub" |> process.new_name |> PubSub(WrappedSimpleMsg),
  )
}

pub fn add_workers(
  supervisor supervisor: static_supervisor.Builder,
  pubsubs pubsubs: PubSubs,
) -> static_supervisor.Builder {
  let _totality = fn(name) {
    // !!! INEXHAUSTIVE PATTERN MATCH ERROR ADD WORKER BELOW
    case name {
      SimpleMsg(..) -> Nil
    }
    // !!! INEXHAUSTIVE PATTERN MATCH ERROR ADD WORKER BELOW
  }

  supervisor
  |> static_supervisor.add(gr.supervised(pubsubs.simple.name))
}


//

const cluster_process_name =
  "app_cluster_pubsub_static_name"

pub opaque type State {
  State
}

pub opaque type PubSub(msg, unified_msg) {
  PubSub(
    name: process.Name(gr.Message(msg)),
    to_unified_msg: fn(msg) -> unified_msg,
  )
}

pub opaque type ClusterMsg(msg) {
  ClusterMsg(
    channel: String,
    msg: msg,
  )

  UnexpectedMsg(
    msg: Dynamic,
  )

  ParseFailure(
    msg: Dynamic,
    err: json.DecodeError,
  )
}

fn decode_cluster_msg(
  dyn dyn: Dynamic,
  decode_msg decode_msg: Decoder(msg),
) -> ClusterMsg(msg) {
  decode.string
  |> decode.map(fn(json) {
    {
      use channel <- decode.field("channel", decode.string)
      use msg <- decode.field("msg", decode_msg)

      decode.success(ClusterMsg(channel:, msg:))
    }
    |> json.parse(json, _)
    |> fn(result) {
      case result {
        Ok(msg) -> msg
        Error(err) -> ParseFailure(msg: dyn, err:)
      }
    }
  })
  |> decode.run(dyn, _)
  |> result.lazy_unwrap(fn() { UnexpectedMsg(msg: dyn) })
}

pub fn supervised(
  supervisor supervisor: static_supervisor.Builder,
  spec spec: Spec(msg),
) -> static_supervisor.Builder {
  supervisor
  |> spec.add_workers(spec.init())
  |> static_supervisor.add(
    supervision.worker(fn() {
      cluster_listener(decode_msg: spec.decode_msg())
      |> actor.start
    })
  )
}

fn cluster_listener(
  decode_msg decode_msg: Decoder(msg),
) -> actor.Builder(State, ClusterMsg(msg), Nil) {
  actor.new_with_initialiser(100, fn(_) {
    actor.initialised(State)
    |> actor.selecting({
      // let self = process.self()
      // let subject = gr.join(todo, todo, self)

      process.new_selector()
      |> process.select_other(decode_cluster_msg(
        dyn: _,
        decode_msg:,
      ))
    })
    |> actor.returning(Nil)
    |> Ok
  })
  |> actor.on_message(listener_loop)
  |> actor.named(unsafe_static_name())
}
fn listener_loop(
  state state: state,
  msg msg: msg,
) -> actor.Next(state, msg) {
  actor.continue(state)
}

pub fn subscribe(
  to to: channel,
  in in: pubsub,
) -> Selector(msg) {
  todo
}

pub fn broadcast(
  to channel: String,
  in pubsub: PubSub(msg, unified_msg),
  msg msg: msg,
) -> Nil {
  pubsub
  |> get_listeners(channel:)
  |> list.each(fn(listener) {
    process.send(listener, msg)
  })
}

fn broadcast_to_cluster(
  to channel: channel,
  in pubsub: pubsub,
  msg msg: msg,
) -> Nil {
}

fn broadcast_locally(
  to channel: channel,
  in pubsub: pubsub,
  msg msg: msg,
) -> Nil {
}

fn get_listeners(
  pubsub pubsub: PubSub(msg, unified_msg),
  channel channel: String,
) -> List(Subject(msg)) {
  []
}

fn unsafe_static_name() -> process.Name(msg) {
  cluster_process_name
  |> atom.create
  |> unsafe_atom_to_name
}

@external(erlang, "app_erl_ffi", "unsafe_cast")
fn unsafe_atom_to_name(
  atom atom: Atom,
) -> process.Name(msg)

// pub fn to_name(
//   val: t,
//   prefix prefix: String,
// ) -> process.Name(msg) {
//   val
//   |> string.inspect
//   |> string.append(to: prefix, suffix: _)
//   |> process.new_name
// }

// DERIVED

pub fn encode_simple_msg(value: SimpleMsg) -> Json {
  case value {
    SimpleMsg(..) as value -> json.object([#("text", json.string(value.text))])
  }
}

pub fn decoder_simple_msg() -> Decoder(SimpleMsg) {
  decode.one_of(decoder_simple_msg_simple_msg(), [])
}

pub fn decoder_simple_msg_simple_msg() -> Decoder(SimpleMsg) {
  use text <- decode.field("text", decode.string)
  decode.success(SimpleMsg(text:))
}

pub fn encode_unified_msg(value: UnifiedMsg) -> Json {
  case value {
    WrappedSimpleMsg(..) as value ->
      json.object([#("msg", encode_simple_msg(value.msg))])
  }
}

pub fn decoder_unified_msg() -> Decoder(UnifiedMsg) {
  decode.one_of(decoder_unified_msg_wrapped_simple_msg(), [])
}

pub fn decoder_unified_msg_wrapped_simple_msg() -> Decoder(UnifiedMsg) {
  use msg <- decode.field("msg", decoder_simple_msg())
  decode.success(WrappedSimpleMsg(msg:))
}
