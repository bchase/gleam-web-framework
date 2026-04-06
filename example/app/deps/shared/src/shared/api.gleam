import fpo/api/ws/client/req.{type Req, create, delete, func, list, read, update}
import fpo/api/ws/types.{type Id, type Action, type ConfirmDelete, type Crud, type Func, type Paginated, type Params, type Record, type Sub, Created, Deleted, Sub, Updated, decoder_action, decoder_crud, decoder_func, decoder_record, decoder_sub, encode_action, encode_crud, encode_func, encode_record, encode_sub}
import deriv/util as deriv
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option}

pub type Err = req.Err

pub type Api {
  //$ derive json encode decode
  Items(crud: Crud(Item, Item, Item, ItemAttr))
  IntToString(func: Func(Int, String))
  SubscribeToItems(sub: Sub(ItemsSubMsg))
}

pub type ItemsSubMsg {
  //$ derive json encode decode
  ItemsSubMsg(action: Action, item: Record(Item))
}

pub type Item {
  //$ derive json encode decode
  Item(
    name: String,
  )
}

pub type ItemAttr {
  //$ derive json encode decode
  ItemName
}

// codegen helpers

pub fn req_subscribe_to_items(
  msg msg: fn(Result(ItemsSubMsg, Err)) -> msg,
) -> Req(Api, msg) {
  req.sub(Sub, SubscribeToItems, decoder_items_sub_msg(),  msg)
}

pub fn req_int_to_string(
  param param: Int,
  msg msg: fn(Result(String, Err)) -> msg,
) -> Req(Api, msg) {
  func(IntToString, param, decode.string, msg)
}

pub fn req_list_items(
  params params: Option(Params(ItemAttr)),
  msg msg: fn(Result(Paginated(Item), Err)) -> msg,
) -> Req(Api, msg) {
  list(Items, params, req.paginated(decoder_item()), msg)
}

pub fn req_read_items(
  id id: Id(Item),
  msg msg: fn(Result(Record(Item), Err)) -> msg,
) -> Req(Api, msg) {
  read(Items, id, decoder_item(), msg)
}

pub fn req_create_items(
  data data: Item,
  msg msg: fn(#(Action, Result(Record(Item), Err))) -> msg,
) -> Req(Api, msg) {
  create(Items, data, decoder_item(), msg |> req.action(Created))
}

pub fn req_update_items(
  id id: Id(Item),
  data data: Item,
  msg msg: fn(#(Action, Result(Record(Item), Err))) -> msg,
) -> Req(Api, msg) {
  update(Items, id, data, decoder_item(), msg |> req.action(Updated))
}

pub fn req_delete_items(
  id id: Id(Item),
  confirm confirm: ConfirmDelete,
  msg msg: fn(#(Action, Result(Record(Item), Err))) -> msg,
) -> Req(Api, msg) {
  delete(Items, id, confirm, decoder_item(), msg |> req.action(Deleted))
}

// DERIVED

pub fn encode_api(value: Api) -> Json {
  case value {
    Items(..) as value ->
      json.object([
        #("_var", json.string("Items")),
        #(
          "crud",
          encode_crud(
            value.crud,
            encode_item,
            encode_item,
            encode_item,
            encode_item_attr,
          ),
        ),
      ])
    IntToString(..) as value ->
      json.object([
        #("_var", json.string("IntToString")),
        #("func", encode_func(value.func, json.int, json.string)),
      ])
    SubscribeToItems(..) as value ->
      json.object([
        #("_var", json.string("SubscribeToItems")),
        #("sub", encode_sub(value.sub, encode_items_sub_msg)),
      ])
  }
}

pub fn decoder_api() -> Decoder(Api) {
  decode.one_of(decoder_api_items(), [
    decoder_api_int_to_string(),
    decoder_api_subscribe_to_items(),
  ])
}

pub fn decoder_api_items() -> Decoder(Api) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Items"))
  use crud <- decode.field(
    "crud",
    decoder_crud(
      decoder_item(),
      decoder_item(),
      decoder_item(),
      decoder_item_attr(),
    ),
  )
  decode.success(Items(crud:))
}

pub fn decoder_api_int_to_string() -> Decoder(Api) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("IntToString"))
  use func <- decode.field("func", decoder_func(decode.int, decode.string))
  decode.success(IntToString(func:))
}

pub fn encode_items_sub_msg(value: ItemsSubMsg) -> Json {
  case value {
    ItemsSubMsg(..) as value ->
      json.object([
        #("action", encode_action(value.action)),
        #("item", encode_record(value.item, encode_item)),
      ])
  }
}

pub fn decoder_items_sub_msg() -> Decoder(ItemsSubMsg) {
  decode.one_of(decoder_items_sub_msg_items_sub_msg(), [])
}

pub fn decoder_items_sub_msg_items_sub_msg() -> Decoder(ItemsSubMsg) {
  use action <- decode.field("action", decoder_action())
  use item <- decode.field("item", decoder_record(decoder_item()))
  decode.success(ItemsSubMsg(action:, item:))
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

pub fn encode_item_attr(value: ItemAttr) -> Json {
  case value {
    ItemName -> json.object([])
  }
}

pub fn decoder_item_attr() -> Decoder(ItemAttr) {
  decode.one_of(decoder_item_attr_item_name(), [])
}

pub fn decoder_item_attr_item_name() -> Decoder(ItemAttr) {
  decode.success(ItemName)
}


pub fn decoder_api_subscribe_to_items() -> Decoder(Api) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("SubscribeToItems"))
  use sub <- decode.field("sub", decoder_sub(decoder_items_sub_msg()))
  decode.success(SubscribeToItems(sub:))
}
