import fpo/monad/app.{type App}
import gleam/list
import spec/config.{type Config}
import spec/db/postgres as db
import fpo/sql

pub type Message {
  //$ derive from spec/sql.ListAllMsgs
  //$ derive from spec/sql.InsertMsg
  Message(
    id: Int,
    text: String,
    //$ from *.msg
  )
}

pub fn list_all(
) -> App(List(Message), Config, pubsub, user) {
  sql.list_all_msgs()
  |> db.many
  |> app.map(list.map(_, from_list_all_msgs_to_message))
}

pub fn insert(
  text msg: String,
) -> App(List(Message), Config, pubsub, user) {
  sql.insert_msg(msg:)
  |> db.many
  |> app.map(list.map(_, from_insert_msg_to_message))
}

// DERIVED

pub fn from_list_all_msgs_to_message(
  list_all_msgs list_all_msgs: sql.ListAllMsgs,
) -> Message {
  Message(id: list_all_msgs.id, text: list_all_msgs.msg)
}

pub fn from_insert_msg_to_message(
  insert_msg insert_msg: sql.InsertMsg,
) -> Message {
  Message(id: insert_msg.id, text: insert_msg.msg)
}
