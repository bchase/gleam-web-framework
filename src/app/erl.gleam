import gleam/erlang/node
import gleam/erlang/process

pub fn node_send(
  node node: node.Node,
  name name: process.Name(t),
  msg msg: msg,
) -> Nil {
  erl_send(#(name, node), msg)
}

@external(erlang, "erlang", "send")
fn erl_send(receiver: #(process.Name(t), node.Node), message: msg) -> Nil
