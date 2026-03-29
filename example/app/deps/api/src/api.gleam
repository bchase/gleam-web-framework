import gleam/option.{type Option, None}
import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}
import gleam/time/timestamp.{type Timestamp}
// import youid/uuid.{type Uuid}
import api/id.{type Id, decoder_id, encode_id}

pub fn main() -> Nil {
  Nil
}

// domain

pub type Item {
  Item(
    name: String,
  )
}

fn item_to_json(item: Item) -> Json {
  let Item(name:) = item
  json.object([
    #("name", json.string(name)),
  ])
}

fn item_decoder() -> Decoder(Item) {
  use name <- decode.field("name", decode.string)
  decode.success(Item(name:))
}

// domain api

pub type Req {
  CrudItems(crud: CrudSimple(Item))
  ReqOther
}

fn req_to_json(req: Req) -> Json {
  case req {
    CrudItems(crud:) -> json.object([
      #("type", json.string("req_items")),
      #("crud", crud_to_json(crud:, create: item_to_json, update: item_to_json)),
    ])
    ReqOther -> json.object([
      #("type", json.string("req_other")),
    ])
  }
}

// domain api json

fn req_decoder() -> Decoder(Req) {
  use variant <- decode.field("type", decode.string)
  case variant {
    "req_items" -> {
      use crud <- decode.field("crud", crud_decoder(item_decoder(), item_decoder()))
      decode.success(CrudItems(crud:))
    }
    "req_other" -> decode.success(ReqOther)
    _ -> decode.failure(ReqOther, "Req")
  }
}

pub fn socket_req_to_json(
  socket_req socket_req: SocketReq(Req),
) -> Json {
  socket_req_to_json_(socket_req:, req: req_to_json)
}

pub fn socket_req_decoder() -> Decoder(SocketReq(Req)) {
  socket_req_decoder_(req: req_decoder())
}

// generic req

pub type SocketReq(req) {
  SocketReq(
    ref: String,
    req: req,
  )
}

pub type CrudCustom(resource, create, update, msg) {
  Crud(Crud(resource, create, update))
  Custom(msg)
}

pub type CrudSimple(resource) = Crud(resource, resource, resource)

pub type Crud(resource, create, update) {
  List(pagination: Option(Pagination))
  Get(id: Id(resource))
  Create(new: create)
  Update(id: Id(resource), new: update)
  Delete(id: Id(resource), confirm: ConfirmDelete)
}

pub type ConfirmDelete {
  ConfirmDelete
}

pub type Pagination {
  Pagination(
    page: Int,
    limit: Int,
  )
}

// generic resp

pub type SocketResp {
  SocketResp(
    ref: String,
    result: Result(String, Err),
  )
}

pub type Payload {
  Payload(
    resource: String,
    json: String,
  )
}

pub type Err {
  Client(err: ClientErr)
  Server(err: ServerErr)
}

pub type ClientErr {
  ReqDecodeErr(err: String)
  NotFound(id: String, detail: Option(String))
  ClientErr(err: String)
}

pub type ServerErr {
  ServerErr(err: String)
}

pub type Resp {
  RespItems(
    resp: Got(Item),
  )
}

pub type Got(resource) {
  GotMany(
    resources: List(Record(resource)),
  )
  GotOne(
    resource: Record(resource),
    action: Option(Action),
  )
}

pub type Record(resource) {
  Record(
    id: Id(resource),
    created_at: Timestamp,
    updated_at: Timestamp,
    resource: resource,
  )
}

pub type Action {
  Created
  Updated
  Deleted
}

fn action_to_json(action: Action) -> Json {
  case action {
    Created -> json.string("created")
    Updated -> json.string("updated")
    Deleted -> json.string("deleted")
  }
}

fn action_decoder() -> Decoder(Action) {
  use variant <- decode.then(decode.string)
  case variant {
    "created" -> decode.success(Created)
    "updated" -> decode.success(Updated)
    "deleted" -> decode.success(Deleted)
    _ -> decode.failure(Created, "Action")
  }
}

// req json

fn socket_req_to_json_(
  socket_req socket_req: SocketReq(req),
  req encode_req: fn(req) -> Json,
) -> Json {
  let SocketReq(ref:, req:) = socket_req
  json.object([
    #("ref", json.string(ref)),
    #("req", encode_req(req)),
  ])
}

fn socket_req_decoder_(
  req decoder_req: Decoder(req),
) -> Decoder(SocketReq(req)) {
  use ref <- decode.field("ref", decode.string)
  use req <- decode.field("req", decoder_req)
  decode.success(SocketReq(ref:, req:))
}

fn crud_to_json(
  crud crud: Crud(resource, create, update),
  create encode_create: fn(create) -> Json,
  update encode_update: fn(update) -> Json,
) -> Json {
  case crud {
    List(pagination:) -> json.object([
      #("type", json.string("list")),
      #("pagination", case pagination {
        option.None -> json.null()
        option.Some(value) -> pagination_to_json(value)
      }),
    ])
    Get(id:) -> json.object([
      #("type", json.string("get")),
      #("id", encode_id(id)),
    ])
    Create(new:) -> json.object([
      #("type", json.string("create")),
      #("new", encode_create(new)),
    ])
    Update(id:, new:) -> json.object([
      #("type", json.string("update")),
      #("id", encode_id(id)),
      #("new", encode_update(new)),
    ])
    Delete(id:, confirm:) -> json.object([
      #("type", json.string("delete")),
      #("id", encode_id(id)),
      #("confirm", confirm_delete_to_json(confirm)),
    ])
  }
}

fn crud_decoder(
  create decoder_create: Decoder(create),
  update decoder_update: Decoder(update),
) -> Decoder(Crud(resource, create, update)) {
  use variant <- decode.field("type", decode.string)
  case variant {
    "list" -> {
      use pagination <- decode.field("pagination", decode.optional(pagination_decoder()))
      decode.success(List(pagination:))
    }
    "get" -> {
      use id <- decode.field("id", decoder_id())
      decode.success(Get(id:))
    }
    "create" -> {
      use new <- decode.field("new", decoder_create)
      decode.success(Create(new:))
    }
    "update" -> {
      use id <- decode.field("id", decoder_id())
      use new <- decode.field("new", decoder_update)
      decode.success(Update(id:, new:))
    }
    "delete" -> {
      use id <- decode.field("id", decoder_id())
      use confirm <- decode.field("confirm", confirm_delete_decoder())
      decode.success(Delete(id:, confirm:))
    }
    _ -> decode.failure(List(None), "Crud")
  }
}

fn pagination_to_json(pagination: Pagination) -> Json {
  let Pagination(page:, limit:) = pagination
  json.object([
    #("page", json.int(page)),
    #("limit", json.int(limit)),
  ])
}

fn pagination_decoder() -> Decoder(Pagination) {
  use page <- decode.field("page", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(Pagination(page:, limit:))
}

fn confirm_delete_to_json(_confirm_delete: ConfirmDelete) -> Json {
  json.string("confirm_delete")
}

fn confirm_delete_decoder() -> Decoder(ConfirmDelete) {
  use variant <- decode.then(decode.string)
  case variant {
    "confirm_delete" -> decode.success(ConfirmDelete)
    _ -> decode.failure(ConfirmDelete, "ConfirmDelete")
  }
}
