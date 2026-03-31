import api/id.{type Id}
import deriv/util as deriv
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option}
import gleam/time/timestamp.{type Timestamp}

// generic req

pub type SocketReq(req) {
  //$ derive json encode decode
  SocketReq(
    ref: String,
    req: req,
  )
}

pub type CrudCustom(resource, create, update, msg) {
  //$ derive json encode decode
  Crud(crud: Crud(resource, create, update))
  Custom(custom: msg)
}

pub type Crud(resource, create, update, ) {
  //$ derive json encode decode
  List(req: ListReq(resource))
  Create(req: CreateReq(resource, create))
  Read(req: ReadReq(resource))
  Update(req: UpdateReq(resource, update))
  Delete(req: DeleteReq(resource))
}

pub type ListReq(resource) {
  //$ derive json encode decode
  ListReq(
    pagination: Option(Pagination),
    // params:
  )
}
pub type CreateReq(resource, create) {
  //$ derive json encode decode
  CreateReq(new: create)
}
pub type ReadReq(resource) {
  //$ derive json encode decode
  ReadReq(id: Id(resource))
}
pub type UpdateReq(resource, update) {
  //$ derive json encode decode
  UpdateReq(new: update)
}
pub type DeleteReq(resource) {
  //$ derive json encode decode
  DeleteReq(id: Id(resource), confirm: ConfirmDelete)
}

pub type ConfirmDelete {
  //$ derive json encode decode
  ConfirmDelete
}

pub type Pagination {
  //$ derive json encode decode
  Pagination(
    page: Int,
    limit: Int,
  )
}

// generic resp

pub type SocketResp(resp) {
  //$ derive json encode decode
  SocketResp(
    ref: String,
    result: Result(resp, Err),
  )
}

pub type Err {
  //$ derive json encode decode
  Client(err: ClientErr)
  Server(err: ServerErr)
}

pub type ClientErr {
  //$ derive json encode decode
  ReqDecodeErr(err: String)
  NotFound(id: String, detail: Option(String))
  ClientErr(err: String)
}

pub type ServerErr {
  //$ derive json encode decode
  ServerErr(err: String)
}

pub type Paginated(t) {
  //$ derive json encode decode
  Paginated(
    resources: List(Record(t)),
    pagination: Pagination,
  )
}

pub type Records(resource) = List(Record(resource))

pub type Record(resource) {
  //$ derive json encode decode
  Record(
    id: Id(resource),
    created_at: Timestamp,
    updated_at: Timestamp,
    resource: resource,
  )
}

pub type Action {
  //$ derive json encode decode
  Created
  Updated
  Deleted
}

// JSON HELPERS

// pub fn encode_crud_simple(
//   crud crud: CrudSimple(t),
//   encode encode: fn(t) -> Json,
// ) -> Json {
//   encode_crud(crud, encode, encode, encode)
// }

// pub fn decoder_crud_simple(
//   decoder decoder: Decoder(t),
// ) -> Decoder(CrudSimple(t)) {
//   decoder_crud(decoder, decoder, decoder)
// }

fn encode_timestamp(
  timestamp timestamp: Timestamp,
) -> Json {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)

  json.object([
    #("s", json.int(seconds)),
    #("ns", json.int(nanoseconds)),
  ])
}

fn decoder_timestamp() -> Decoder(Timestamp) {
  use s <- decode.field("s", decode.int)
  use ns <- decode.field("ns", decode.int)

  decode.success(timestamp.from_unix_seconds_and_nanoseconds(s, ns))
}

// TODO impl `Result` in deriv

fn encode_result(
  result result: Result(t, err),
  encode_ok encode_ok: fn(t) -> Json,
  encode_error encode_error: fn(err) -> Json,
) -> Json {
  case result {
    Ok(x) -> json.object([#("ok", encode_ok(x))])
    Error(err) -> json.object([#("error", encode_error(err))])
  }
}

fn decoder_result(
  decoder_ok decoder_ok: Decoder(t),
  decoder_error decoder_error: Decoder(err),
) -> Decoder(Result(t, err)) {
  decode.one_of(
    decoder_result_ok(decoder_ok:),
    [decoder_result_err(decoder_error:)]
  )
}

fn decoder_result_ok(
  decoder_ok decoder_ok: Decoder(t),
) -> Decoder(Result(t, err)) {
  use x <- decode.field("ok", decoder_ok)
  decode.success(Ok(x))
}

fn decoder_result_err(
  decoder_error decoder_error: Decoder(err),
) -> Decoder(Result(t, err)) {
  use err <- decode.field("error", decoder_error)
  decode.success(Error(err))
}

// TODO detect phantom types in deriv

fn decoder_id(
  _decoder_resource: Decoder(resource),
) -> Decoder(Id(resource)) {
  id.decoder_id()
}

fn encode_id(
  id: Id(resource),
  _encode_resource: fn(resoure) -> Json,
) -> Json {
  id.encode_id(id)
}

// DERIVED

pub fn encode_socket_req(
  value: SocketReq(req),
  encode_req: fn(req) -> Json,
) -> Json {
  case value {
    SocketReq(..) as value ->
      json.object([
        #("ref", json.string(value.ref)),
        #("req", encode_req(value.req)),
      ])
  }
}

pub fn decoder_socket_req(decoder_req: Decoder(req)) -> Decoder(SocketReq(req)) {
  decode.one_of(decoder_socket_req_socket_req(decoder_req), [])
}

pub fn decoder_socket_req_socket_req(
  decoder_req: Decoder(req),
) -> Decoder(SocketReq(req)) {
  use ref <- decode.field("ref", decode.string)
  use req <- decode.field("req", decoder_req)
  decode.success(SocketReq(ref:, req:))
}

pub fn encode_crud_custom(
  value: CrudCustom(resource, create, update, msg),
  encode_resource: fn(resource) -> Json,
  encode_create: fn(create) -> Json,
  encode_update: fn(update) -> Json,
  encode_msg: fn(msg) -> Json,
) -> Json {
  case value {
    Crud(..) as value ->
      json.object([
        #("_var", json.string("Crud")),
        #(
          "crud",
          encode_crud(value.crud, encode_resource, encode_create, encode_update),
        ),
      ])
    Custom(..) as value ->
      json.object([
        #("_var", json.string("Custom")),
        #("custom", encode_msg(value.custom)),
      ])
  }
}

pub fn decoder_crud_custom(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
  decoder_msg: Decoder(msg),
) -> Decoder(CrudCustom(resource, create, update, msg)) {
  decode.one_of(
    decoder_crud_custom_crud(
      decoder_resource,
      decoder_create,
      decoder_update,
      decoder_msg,
    ),
    [
      decoder_crud_custom_custom(
        decoder_resource,
        decoder_create,
        decoder_update,
        decoder_msg,
      ),
    ],
  )
}

pub fn decoder_crud_custom_crud(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
  decoder_msg: Decoder(msg),
) -> Decoder(CrudCustom(resource, create, update, msg)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Crud"))
  use crud <- decode.field(
    "crud",
    decoder_crud(decoder_resource, decoder_create, decoder_update),
  )
  decode.success(Crud(crud:))
}

pub fn decoder_crud_custom_custom(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
  decoder_msg: Decoder(msg),
) -> Decoder(CrudCustom(resource, create, update, msg)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Custom"))
  use custom <- decode.field("custom", decoder_msg)
  decode.success(Custom(custom:))
}

pub fn encode_crud(
  value: Crud(resource, create, update),
  encode_resource: fn(resource) -> Json,
  encode_create: fn(create) -> Json,
  encode_update: fn(update) -> Json,
) -> Json {
  case value {
    List(..) as value ->
      json.object([
        #("_var", json.string("List")),
        #("req", encode_list_req(value.req)),
      ])
    Create(..) as value ->
      json.object([
        #("_var", json.string("Create")),
        #("req", encode_create_req(value.req, encode_create)),
      ])
    Read(..) as value ->
      json.object([
        #("_var", json.string("Read")),
        #("req", encode_read_req(value.req, encode_resource)),
      ])
    Update(..) as value ->
      json.object([
        #("_var", json.string("Update")),
        #("req", encode_update_req(value.req, encode_update)),
      ])
    Delete(..) as value ->
      json.object([
        #("_var", json.string("Delete")),
        #("req", encode_delete_req(value.req, encode_resource)),
      ])
  }
}

pub fn decoder_crud(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
) -> Decoder(Crud(resource, create, update)) {
  decode.one_of(
    decoder_crud_list(decoder_resource, decoder_create, decoder_update),
    [
      decoder_crud_create(decoder_resource, decoder_create, decoder_update),
      decoder_crud_read(decoder_resource, decoder_create, decoder_update),
      decoder_crud_update(decoder_resource, decoder_create, decoder_update),
      decoder_crud_delete(decoder_resource, decoder_create, decoder_update),
    ],
  )
}

pub fn decoder_crud_list(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
) -> Decoder(Crud(resource, create, update)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("List"))
  use req <- decode.field("req", decoder_list_req())
  decode.success(List(req:))
}

pub fn decoder_crud_create(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
) -> Decoder(Crud(resource, create, update)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Create"))
  use req <- decode.field("req", decoder_create_req(decoder_create))
  decode.success(Create(req:))
}

pub fn decoder_crud_read(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
) -> Decoder(Crud(resource, create, update)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Read"))
  use req <- decode.field("req", decoder_read_req(decoder_resource))
  decode.success(Read(req:))
}

pub fn decoder_crud_update(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
) -> Decoder(Crud(resource, create, update)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Update"))
  use req <- decode.field("req", decoder_update_req(decoder_update))
  decode.success(Update(req:))
}

pub fn decoder_crud_delete(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
) -> Decoder(Crud(resource, create, update)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Delete"))
  use req <- decode.field("req", decoder_delete_req(decoder_resource))
  decode.success(Delete(req:))
}

pub fn encode_list_req(value: ListReq(resource)) -> Json {
  case value {
    ListReq(..) as value ->
      json.object([
        #("pagination", json.nullable(value.pagination, encode_pagination)),
      ])
  }
}

pub fn decoder_list_req() -> Decoder(ListReq(resource)) {
  decode.one_of(decoder_list_req_list_req(), [])
}

pub fn decoder_list_req_list_req() -> Decoder(ListReq(resource)) {
  use pagination <- decode.optional_field(
    "pagination",
    deriv.none,
    decode.optional(decoder_pagination()),
  )
  decode.success(ListReq(pagination:))
}

pub fn encode_create_req(
  value: CreateReq(resource, create),
  encode_create: fn(create) -> Json,
) -> Json {
  case value {
    CreateReq(..) as value -> json.object([#("new", encode_create(value.new))])
  }
}

pub fn decoder_create_req(
  decoder_create: Decoder(create),
) -> Decoder(CreateReq(resource, create)) {
  decode.one_of(decoder_create_req_create_req(decoder_create), [])
}

pub fn decoder_create_req_create_req(
  decoder_create: Decoder(create),
) -> Decoder(CreateReq(resource, create)) {
  use new <- decode.field("new", decoder_create)
  decode.success(CreateReq(new:))
}

pub fn encode_read_req(
  value: ReadReq(resource),
  encode_resource: fn(resource) -> Json,
) -> Json {
  case value {
    ReadReq(..) as value ->
      json.object([#("id", encode_id(value.id, encode_resource))])
  }
}

pub fn decoder_read_req(
  decoder_resource: Decoder(resource),
) -> Decoder(ReadReq(resource)) {
  decode.one_of(decoder_read_req_read_req(decoder_resource), [])
}

pub fn decoder_read_req_read_req(
  decoder_resource: Decoder(resource),
) -> Decoder(ReadReq(resource)) {
  use id <- decode.field("id", decoder_id(decoder_resource))
  decode.success(ReadReq(id:))
}

pub fn encode_update_req(
  value: UpdateReq(resource, update),
  encode_update: fn(update) -> Json,
) -> Json {
  case value {
    UpdateReq(..) as value -> json.object([#("new", encode_update(value.new))])
  }
}

pub fn decoder_update_req(
  decoder_update: Decoder(update),
) -> Decoder(UpdateReq(resource, update)) {
  decode.one_of(decoder_update_req_update_req(decoder_update), [])
}

pub fn decoder_update_req_update_req(
  decoder_update: Decoder(update),
) -> Decoder(UpdateReq(resource, update)) {
  use new <- decode.field("new", decoder_update)
  decode.success(UpdateReq(new:))
}

pub fn encode_delete_req(
  value: DeleteReq(resource),
  encode_resource: fn(resource) -> Json,
) -> Json {
  case value {
    DeleteReq(..) as value ->
      json.object([
        #("confirm", encode_confirm_delete(value.confirm)),
        #("id", encode_id(value.id, encode_resource)),
      ])
  }
}

pub fn decoder_delete_req(
  decoder_resource: Decoder(resource),
) -> Decoder(DeleteReq(resource)) {
  decode.one_of(decoder_delete_req_delete_req(decoder_resource), [])
}

pub fn decoder_delete_req_delete_req(
  decoder_resource: Decoder(resource),
) -> Decoder(DeleteReq(resource)) {
  use id <- decode.field("id", decoder_id(decoder_resource))
  use confirm <- decode.field("confirm", decoder_confirm_delete())
  decode.success(DeleteReq(id:, confirm:))
}

pub fn encode_confirm_delete(value: ConfirmDelete) -> Json {
  case value {
    ConfirmDelete -> json.object([])
  }
}

pub fn decoder_confirm_delete() -> Decoder(ConfirmDelete) {
  decode.one_of(decoder_confirm_delete_confirm_delete(), [])
}

pub fn decoder_confirm_delete_confirm_delete() -> Decoder(ConfirmDelete) {
  decode.success(ConfirmDelete)
}

pub fn encode_pagination(value: Pagination) -> Json {
  case value {
    Pagination(..) as value ->
      json.object([
        #("limit", json.int(value.limit)),
        #("page", json.int(value.page)),
      ])
  }
}

pub fn decoder_pagination() -> Decoder(Pagination) {
  decode.one_of(decoder_pagination_pagination(), [])
}

pub fn decoder_pagination_pagination() -> Decoder(Pagination) {
  use page <- decode.field("page", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(Pagination(page:, limit:))
}

pub fn encode_socket_resp(
  value: SocketResp(resp),
  encode_resp: fn(resp) -> Json,
) -> Json {
  case value {
    SocketResp(..) as value ->
      json.object([
        #("ref", json.string(value.ref)),
        #("result", encode_result(value.result, encode_resp, encode_err)),
      ])
  }
}

pub fn decoder_socket_resp(
  decoder_resp: Decoder(resp),
) -> Decoder(SocketResp(resp)) {
  decode.one_of(decoder_socket_resp_socket_resp(decoder_resp), [])
}

pub fn decoder_socket_resp_socket_resp(
  decoder_resp: Decoder(resp),
) -> Decoder(SocketResp(resp)) {
  use ref <- decode.field("ref", decode.string)
  use result <- decode.field(
    "result",
    decoder_result(decoder_resp, decoder_err()),
  )
  decode.success(SocketResp(ref:, result:))
}

pub fn encode_err(value: Err) -> Json {
  case value {
    Client(..) as value ->
      json.object([
        #("_var", json.string("Client")),
        #("err", encode_client_err(value.err)),
      ])
    Server(..) as value ->
      json.object([
        #("_var", json.string("Server")),
        #("err", encode_server_err(value.err)),
      ])
  }
}

pub fn decoder_err() -> Decoder(Err) {
  decode.one_of(decoder_err_client(), [decoder_err_server()])
}

pub fn decoder_err_client() -> Decoder(Err) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Client"))
  use err <- decode.field("err", decoder_client_err())
  decode.success(Client(err:))
}

pub fn decoder_err_server() -> Decoder(Err) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Server"))
  use err <- decode.field("err", decoder_server_err())
  decode.success(Server(err:))
}

pub fn encode_client_err(value: ClientErr) -> Json {
  case value {
    ReqDecodeErr(..) as value ->
      json.object([
        #("_var", json.string("ReqDecodeErr")),
        #("err", json.string(value.err)),
      ])
    NotFound(..) as value ->
      json.object([
        #("_var", json.string("NotFound")),
        #("detail", json.nullable(value.detail, json.string)),
        #("id", json.string(value.id)),
      ])
    ClientErr(..) as value ->
      json.object([
        #("_var", json.string("ClientErr")),
        #("err", json.string(value.err)),
      ])
  }
}

pub fn decoder_client_err() -> Decoder(ClientErr) {
  decode.one_of(decoder_client_err_req_decode_err(), [
    decoder_client_err_not_found(),
    decoder_client_err_client_err(),
  ])
}

pub fn decoder_client_err_req_decode_err() -> Decoder(ClientErr) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("ReqDecodeErr"))
  use err <- decode.field("err", decode.string)
  decode.success(ReqDecodeErr(err:))
}

pub fn decoder_client_err_not_found() -> Decoder(ClientErr) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("NotFound"))
  use id <- decode.field("id", decode.string)
  use detail <- decode.optional_field(
    "detail",
    deriv.none,
    decode.optional(decode.string),
  )
  decode.success(NotFound(id:, detail:))
}

pub fn decoder_client_err_client_err() -> Decoder(ClientErr) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("ClientErr"))
  use err <- decode.field("err", decode.string)
  decode.success(ClientErr(err:))
}

pub fn encode_server_err(value: ServerErr) -> Json {
  case value {
    ServerErr(..) as value -> json.object([#("err", json.string(value.err))])
  }
}

pub fn decoder_server_err() -> Decoder(ServerErr) {
  decode.one_of(decoder_server_err_server_err(), [])
}

pub fn decoder_server_err_server_err() -> Decoder(ServerErr) {
  use err <- decode.field("err", decode.string)
  decode.success(ServerErr(err:))
}

pub fn encode_paginated(value: Paginated(t), encode_t: fn(t) -> Json) -> Json {
  case value {
    Paginated(..) as value ->
      json.object([
        #("pagination", encode_pagination(value.pagination)),
        #("resources", json.array(value.resources, encode_record(_, encode_t))),
      ])
  }
}

pub fn decoder_paginated(decoder_t: Decoder(t)) -> Decoder(Paginated(t)) {
  decode.one_of(decoder_paginated_paginated(decoder_t), [])
}

pub fn decoder_paginated_paginated(
  decoder_t: Decoder(t),
) -> Decoder(Paginated(t)) {
  use resources <- decode.field(
    "resources",
    decode.list(decoder_record(decoder_t)),
  )
  use pagination <- decode.field("pagination", decoder_pagination())
  decode.success(Paginated(resources:, pagination:))
}

pub fn encode_record(
  value: Record(resource),
  encode_resource: fn(resource) -> Json,
) -> Json {
  case value {
    Record(..) as value ->
      json.object([
        #("created_at", encode_timestamp(value.created_at)),
        #("id", encode_id(value.id, encode_resource)),
        #("resource", encode_resource(value.resource)),
        #("updated_at", encode_timestamp(value.updated_at)),
      ])
  }
}

pub fn decoder_record(
  decoder_resource: Decoder(resource),
) -> Decoder(Record(resource)) {
  decode.one_of(decoder_record_record(decoder_resource), [])
}

pub fn decoder_record_record(
  decoder_resource: Decoder(resource),
) -> Decoder(Record(resource)) {
  use id <- decode.field("id", decoder_id(decoder_resource))
  use created_at <- decode.field("created_at", decoder_timestamp())
  use updated_at <- decode.field("updated_at", decoder_timestamp())
  use resource <- decode.field("resource", decoder_resource)
  decode.success(Record(id:, created_at:, updated_at:, resource:))
}

pub fn encode_action(value: Action) -> Json {
  case value {
    Created -> json.object([#("_var", json.string("Created"))])
    Updated -> json.object([#("_var", json.string("Updated"))])
    Deleted -> json.object([#("_var", json.string("Deleted"))])
  }
}

pub fn decoder_action() -> Decoder(Action) {
  decode.one_of(decoder_action_created(), [
    decoder_action_updated(),
    decoder_action_deleted(),
  ])
}

pub fn decoder_action_created() -> Decoder(Action) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Created"))
  decode.success(Created)
}

pub fn decoder_action_updated() -> Decoder(Action) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Updated"))
  decode.success(Updated)
}

pub fn decoder_action_deleted() -> Decoder(Action) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Deleted"))
  decode.success(Deleted)
}
