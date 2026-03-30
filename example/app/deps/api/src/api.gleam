import deriv/util as deriv
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import api/generic.{type CrudSimple, type Got, type SocketReq, type SocketResp, encode_socket_req, encode_socket_resp, decoder_socket_req, decoder_socket_resp, encode_crud_simple, decoder_crud_simple, encode_got, decoder_got}

pub fn main() -> Nil {
  Nil
}

// domain

pub type Item {
  //$ derive json encode decode
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


// domain api

pub type Req {
  //$ derive json encode decode
  CrudItems(crud: CrudSimple(Item))
  ReqOther
}

pub type Resp {
  //$ derive json encode decode
  RespItems(resp: Got(Item))
  RespOther
}

pub fn encode_socket_req_(
  value: SocketReq(Req),
) -> Json {
  encode_socket_req(value, encode_req)
}

pub fn decoder_socket_req_(
) -> Decoder(SocketReq(Req)) {
  decoder_socket_req(decoder_req())
}

pub fn encode_socket_resp_(
  value: SocketResp(Resp),
) -> Json {
  encode_socket_resp(value, encode_resp)
}

pub fn decoder_socket_resp_(
) -> Decoder(SocketResp(Resp)) {
  decoder_socket_resp(decoder_resp())
}

// DERIVED DOMAIN

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
    RespItems(..) as value ->
      json.object([
        #("_var", json.string("RespItems")),
        #("resp", encode_got(value.resp, encode_item)),
      ])
    RespOther -> json.object([#("_var", json.string("RespOther"))])
  }
}

pub fn decoder_resp() -> Decoder(Resp) {
  decode.one_of(decoder_resp_resp_items(), [decoder_resp_resp_other()])
}

pub fn decoder_resp_resp_items() -> Decoder(Resp) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("RespItems"))
  use resp <- decode.field("resp", decoder_got(decoder_item()))
  decode.success(RespItems(resp:))
}

pub fn decoder_resp_resp_other() -> Decoder(Resp) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("RespOther"))
  decode.success(RespOther)
}
