import api/generic.{type Action, type Crud, type Paginated, decoder_action, decoder_crud, decoder_paginated, decoder_record, encode_action, encode_crud, encode_paginated, encode_record}
import api/id.{type Id}
import deriv/util as deriv
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub fn main() -> Nil {
  Nil
}

// TODO detect phantom types in `deriv`
fn encode_id(value, _) { id.encode_id(value) }
fn decoder_id(_) { id.decoder_id() }
// TODO detect phantom types in `deriv`

pub type Record(t) = generic.Record(t)

pub type SocketReq = generic.SocketReq(Req)
pub type SocketResp = generic.SocketResp(Resp)
pub type Err = generic.Err

pub fn socket_req(
  ref ref: String,
  req req: Req,
) -> generic.SocketReq(Req) {
  generic.SocketReq(ref:, req:)
}

pub fn socket_resp(
  ref ref: String,
  result result: Result(Resp, Err),
) -> generic.SocketResp(Resp) {
  generic.SocketResp(ref:, result:)
}

pub fn zero_err(
) -> Err {
  generic.Server(err: generic.ServerErr(""))
}

// domain

pub type Item {
  //$ derive json encode decode
  //$ derive zero
  Item(
    name: String,
  )
}

pub fn encode_item(value: Item) -> Json {
  case value {
    Item(..) as value -> json.object([#("name", json.string(value.name))])
  }
}

pub fn decoder_item() -> Decoder(Item) {
  decode.one_of(decoder_item_item(), [])
}

pub fn decoder_item_item() -> Decoder(Item) {
  use name <- decode.field("name", decode.string)
  decode.success(Item(name:))
}

pub fn zero_item() -> Item {
  Item("")
}


// experimental api

  //$ derive json encode decode
pub type ExpReq {
  Items(crud: Crud(Item, Item, Item, Nil))
}

// domain api

pub type Req {
  //$ derive json encode decode
  CrudItems(crud: Crud(Item, Item, Item, Nil))
  Subscribe(subs: Dict(String, Subscription))
  ReqOther
}

pub type Subscription {
  //$ derive json encode decode
  SubItems
  SubItem(id: Id(Item))
}

pub type Resp {
  //$ derive json encode decode
  GotItems(page: Paginated(Item))
  GotItem(item: Record(Item), action: Action)
  SubscribedTo(all_subs: Dict(String, Subscription))
  RespOther
}

pub fn encode_socket_req(
  value: generic.SocketReq(Req),
) -> Json {
  generic.encode_socket_req(value, encode_req)
}

pub fn decoder_socket_req(
) -> Decoder(generic.SocketReq(Req)) {
  generic.decoder_socket_req(decoder_req())
}

pub fn encode_socket_resp(
  value: generic.SocketResp(Resp),
) -> Json {
  generic.encode_socket_resp(value, encode_resp)
}

pub fn decoder_socket_resp(
) -> Decoder(generic.SocketResp(Resp)) {
  generic.decoder_socket_resp(decoder_resp())
}

fn encode_nil(
  value _value: Nil,
) -> Json {
  json.null()
}

fn decoder_nil() -> Decoder(Nil) {
  decode.success(Nil)
}

// DERIVED

pub fn encode_req(value: Req) -> Json {
  case value {
    CrudItems(..) as value ->
      json.object([
        #("_var", json.string("CrudItems")),
        #(
          "crud",
          encode_crud(
            value.crud,
            encode_item,
            encode_item,
            encode_item,
            encode_nil,
          ),
        ),
      ])
    Subscribe(..) as value ->
      json.object([
        #("_var", json.string("Subscribe")),
        #("subs", json.dict(value.subs, fn(str) { str }, encode_subscription)),
      ])
    ReqOther -> json.object([#("_var", json.string("ReqOther"))])
  }
}

pub fn decoder_req() -> Decoder(Req) {
  decode.one_of(decoder_req_crud_items(), [
    decoder_req_subscribe(),
    decoder_req_req_other(),
  ])
}

pub fn decoder_req_crud_items() -> Decoder(Req) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("CrudItems"))
  use crud <- decode.field(
    "crud",
    decoder_crud(decoder_item(), decoder_item(), decoder_item(), decoder_nil()),
  )
  decode.success(CrudItems(crud:))
}

pub fn decoder_req_subscribe() -> Decoder(Req) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Subscribe"))
  use subs <- decode.field(
    "subs",
    decode.dict(decode.string, decoder_subscription()),
  )
  decode.success(Subscribe(subs:))
}

pub fn decoder_req_req_other() -> Decoder(Req) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("ReqOther"))
  decode.success(ReqOther)
}

pub fn encode_subscription(value: Subscription) -> Json {
  case value {
    SubItems -> json.object([#("_var", json.string("SubItems"))])
    SubItem(..) as value ->
      json.object([
        #("_var", json.string("SubItem")),
        #("id", encode_id(value.id, encode_item)),
      ])
  }
}

pub fn decoder_subscription() -> Decoder(Subscription) {
  decode.one_of(decoder_subscription_sub_items(), [
    decoder_subscription_sub_item(),
  ])
}

pub fn decoder_subscription_sub_items() -> Decoder(Subscription) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("SubItems"))
  decode.success(SubItems)
}

pub fn decoder_subscription_sub_item() -> Decoder(Subscription) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("SubItem"))
  use id <- decode.field("id", decoder_id(decoder_item()))
  decode.success(SubItem(id:))
}

pub fn encode_resp(value: Resp) -> Json {
  case value {
    GotItems(..) as value ->
      json.object([
        #("_var", json.string("GotItems")),
        #("page", encode_paginated(value.page, encode_item)),
      ])
    GotItem(..) as value ->
      json.object([
        #("_var", json.string("GotItem")),
        #("action", encode_action(value.action)),
        #("item", encode_record(value.item, encode_item)),
      ])
    SubscribedTo(..) as value ->
      json.object([
        #("_var", json.string("SubscribedTo")),
        #(
          "all_subs",
          json.dict(value.all_subs, fn(str) { str }, encode_subscription),
        ),
      ])
    RespOther -> json.object([#("_var", json.string("RespOther"))])
  }
}

pub fn decoder_resp() -> Decoder(Resp) {
  decode.one_of(decoder_resp_got_items(), [
    decoder_resp_got_item(),
    decoder_resp_subscribed_to(),
    decoder_resp_resp_other(),
  ])
}

pub fn decoder_resp_got_items() -> Decoder(Resp) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("GotItems"))
  use page <- decode.field("page", decoder_paginated(decoder_item()))
  decode.success(GotItems(page:))
}

pub fn decoder_resp_got_item() -> Decoder(Resp) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("GotItem"))
  use item <- decode.field("item", decoder_record(decoder_item()))
  use action <- decode.field("action", decoder_action())
  decode.success(GotItem(item:, action:))
}

pub fn decoder_resp_subscribed_to() -> Decoder(Resp) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("SubscribedTo"))
  use all_subs <- decode.field(
    "all_subs",
    decode.dict(decode.string, decoder_subscription()),
  )
  decode.success(SubscribedTo(all_subs:))
}

pub fn decoder_resp_resp_other() -> Decoder(Resp) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("RespOther"))
  decode.success(RespOther)
}