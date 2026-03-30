import api/generic.{type CrudSimple, type Got, type ManyRecords, type Record, decoder_crud_simple, decoder_got, decoder_many_records, decoder_record, encode_crud_simple, encode_got, encode_many_records, encode_record}
import deriv/util as deriv
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub fn main() -> Nil {
  Nil
}

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


// domain api

pub type Req {
  //$ derive json encode decode
  CrudItems(crud: CrudSimple(Item))
  ReqOther
}

pub type Resp {
  //$ derive json encode decode
  GotItems(page: ManyRecords(Item))
  GotItem(item: Record(Item))
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

// DERIVED

pub fn encode_req(value: Req) -> Json {
  case value {
    CrudItems(..) as value ->
      json.object([
        #("_var", json.string("CrudItems")),
        #("crud", encode_crud_simple(value.crud, encode_item)),
      ])
    ReqOther -> json.object([#("_var", json.string("ReqOther"))])
  }
}

pub fn decoder_req() -> Decoder(Req) {
  decode.one_of(decoder_req_crud_items(), [decoder_req_req_other()])
}

pub fn decoder_req_crud_items() -> Decoder(Req) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("CrudItems"))
  use crud <- decode.field("crud", decoder_crud_simple(decoder_item()))
  decode.success(CrudItems(crud:))
}

pub fn decoder_req_req_other() -> Decoder(Req) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("ReqOther"))
  decode.success(ReqOther)
}

pub fn encode_resp(value: Resp) -> Json {
  case value {
    GotItems(..) as value ->
      json.object([
        #("_var", json.string("GotItems")),
        #("page", encode_many_records(value.page, encode_item)),
      ])
    GotItem(..) as value ->
      json.object([
        #("_var", json.string("GotItem")),
        #("item", encode_record(value.item, encode_item)),
      ])
    RespOther -> json.object([#("_var", json.string("RespOther"))])
  }
}

pub fn decoder_resp_resp_other() -> Decoder(Resp) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("RespOther"))
  decode.success(RespOther)
}


pub fn decoder_resp_got_items() -> Decoder(Resp) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("GotItems"))
  use page <- decode.field("page", decoder_many_records(decoder_item()))
  decode.success(GotItems(page:))
}

pub fn decoder_resp_got_item() -> Decoder(Resp) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("GotItem"))
  use item <- decode.field("item", decoder_record(decoder_item()))
  decode.success(GotItem(item:))
}


pub fn decoder_resp() -> Decoder(Resp) {
  decode.one_of(decoder_resp_got_items(), [
    decoder_resp_got_item(),
    decoder_resp_resp_other(),
  ])
}