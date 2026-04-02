import api/id.{type Id}
import deriv/util as deriv
import gleam/dynamic/decode.{type Decoder}
import gleam/function
import gleam/json.{type Json}
import gleam/option.{type Option}
import gleam/order.{type Order}
import gleam/time/timestamp.{type Timestamp}
import youid/uuid.{type Uuid}

// generic req

pub type SocketReq(req) {
  //$ derive json encode decode
  SocketReq(
    ref: Uuid,
    req: req,
  )
}

pub fn encode_uuid(
  value value: Uuid,
) -> Json {
  value
  |> uuid.to_string
  |> json.string
}

pub fn decoder_uuid() -> Decoder(Uuid) {
  decode.string
  |> decode.then(fn(str) {
    case uuid.from_string(str) {
      Ok(uuid) -> decode.success(uuid)
      Error(Nil) -> decode.failure(uuid.v7_from_millisec(0), "Uuid")
    }
  })
}

pub type Func(param, return) {
  //$ derive json encode decode
  Func(req: FuncReq(param, return))
}

pub type Crud(resource, create, update, key) {
  //$ derive json encode decode
  List(req: ListReq(resource, key))
  Create(req: CreateReq(resource, create))
  Read(req: ReadReq(resource))
  Update(req: UpdateReq(resource, update))
  Delete(req: DeleteReq(resource))
}

pub type Params(key) {
  //$ derive json encode decode
  Params(
    // filter: Option(AndOr(Filter(key))),
    sort: List(Sort(key)),
    params: List(Param),
    pagination: Option(Pagination),
  )
}

pub type Param {
  //$ derive json encode decode
  Param(
    key: String,
    val: String,
  )
}

pub type Sort(key) {
  //$ derive json encode decode
  Sort(
    key: key,
    dir: Dir,
  )
}

pub type Dir {
  //$ derive json encode decode
  Asc
  Desc
}

//pub type Filter(key) {
//  //$ derive json encode decode
//  Filter(
//    key: key,
//    ord: Order,
//    val: GleamType,
//  )
//}

//pub type AndOr(t) {
//  And(left: AndOr(t), right: AndOr(t))
//  Or(left: AndOr(t), right: AndOr(t))
//  Just(val: t)
//}

//pub type GleamType {
//  String(str: String)
//  Int(int: Int)
//  Float(float: Float)
//  Bool(bool: Bool)
//  BitArray(ba: BitArray)
//}

pub type FuncReq(param, return) {
  //$ derive json encode decode
  FuncReq(param: param)
}

pub type ListReq(resource, key) {
  //$ derive json encode decode
  ListReq(params: Option(Params(key)))
}
pub type CreateReq(resource, create) {
  //$ derive json encode decode
  CreateReq(data: create)
}
pub type ReadReq(resource) {
  //$ derive json encode decode
  ReadReq(id: Id(resource))
}
pub type UpdateReq(resource, update) {
  //$ derive json encode decode
  UpdateReq(id: Id(resource), data: update)
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

pub type SocketResp {
  SocketResp(
    ref: Uuid,
    action: Option(Action),
    result: Result(Json, Err),
  )
}

pub fn encode_socket_resp(
  value: SocketResp,
) -> Json {
  json.object([
    #("ref", value.ref |> uuid.to_string |> json.string),
    #("result", value.result |> encode_result(function.identity, encode_err)),
  ])
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

pub fn decoder_result(
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
        #("ref", encode_uuid(value.ref)),
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
  use ref <- decode.field("ref", decoder_uuid())
  use req <- decode.field("req", decoder_req)
  decode.success(SocketReq(ref:, req:))
}

pub fn encode_crud(
  value: Crud(resource, create, update, key),
  encode_resource: fn(resource) -> Json,
  encode_create: fn(create) -> Json,
  encode_update: fn(update) -> Json,
  encode_key: fn(key) -> Json,
) -> Json {
  case value {
    List(..) as value ->
      json.object([
        #("_var", json.string("List")),
        #("req", encode_list_req(value.req, encode_key)),
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
        #("req", encode_update_req(value.req, encode_resource, encode_update)),
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
  decoder_key: Decoder(key),
) -> Decoder(Crud(resource, create, update, key)) {
  decode.one_of(
    decoder_crud_list(
      decoder_resource,
      decoder_create,
      decoder_update,
      decoder_key,
    ),
    [
      decoder_crud_create(
        decoder_resource,
        decoder_create,
        decoder_update,
        decoder_key,
      ),
      decoder_crud_read(
        decoder_resource,
        decoder_create,
        decoder_update,
        decoder_key,
      ),
      decoder_crud_update(
        decoder_resource,
        decoder_create,
        decoder_update,
        decoder_key,
      ),
      decoder_crud_delete(
        decoder_resource,
        decoder_create,
        decoder_update,
        decoder_key,
      ),
    ],
  )
}

pub fn decoder_crud_list(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
  decoder_key: Decoder(key),
) -> Decoder(Crud(resource, create, update, key)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("List"))
  use req <- decode.field("req", decoder_list_req(decoder_key))
  decode.success(List(req:))
}

pub fn decoder_crud_create(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
  decoder_key: Decoder(key),
) -> Decoder(Crud(resource, create, update, key)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Create"))
  use req <- decode.field("req", decoder_create_req(decoder_create))
  decode.success(Create(req:))
}

pub fn decoder_crud_read(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
  decoder_key: Decoder(key),
) -> Decoder(Crud(resource, create, update, key)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Read"))
  use req <- decode.field("req", decoder_read_req(decoder_resource))
  decode.success(Read(req:))
}

pub fn decoder_crud_update(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
  decoder_key: Decoder(key),
) -> Decoder(Crud(resource, create, update, key)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Update"))
  use req <- decode.field(
    "req",
    decoder_update_req(decoder_resource, decoder_update),
  )
  decode.success(Update(req:))
}

pub fn decoder_crud_delete(
  decoder_resource: Decoder(resource),
  decoder_create: Decoder(create),
  decoder_update: Decoder(update),
  decoder_key: Decoder(key),
) -> Decoder(Crud(resource, create, update, key)) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Delete"))
  use req <- decode.field("req", decoder_delete_req(decoder_resource))
  decode.success(Delete(req:))
}

pub fn encode_list_req(
  value: ListReq(resource, key),
  encode_key: fn(key) -> Json,
) -> Json {
  case value {
    ListReq(..) as value ->
      json.object([
        #("params", json.nullable(value.params, encode_params(_, encode_key))),
      ])
  }
}

pub fn decoder_list_req(
  decoder_key: Decoder(key),
) -> Decoder(ListReq(resource, key)) {
  decode.one_of(decoder_list_req_list_req(decoder_key), [])
}

pub fn decoder_list_req_list_req(
  decoder_key: Decoder(key),
) -> Decoder(ListReq(resource, key)) {
  use params <- decode.optional_field(
    "params",
    deriv.none,
    decode.optional(decoder_params(decoder_key)),
  )
  decode.success(ListReq(params:))
}

pub fn encode_create_req(
  value: CreateReq(resource, create),
  encode_create: fn(create) -> Json,
) -> Json {
  case value {
    CreateReq(..) as value ->
      json.object([#("data", encode_create(value.data))])
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
  use data <- decode.field("data", decoder_create)
  decode.success(CreateReq(data:))
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
  encode_resource: fn(resource) -> Json,
  encode_update: fn(update) -> Json,
) -> Json {
  case value {
    UpdateReq(..) as value ->
      json.object([
        #("data", encode_update(value.data)),
        #("id", encode_id(value.id, encode_resource)),
      ])
  }
}

pub fn decoder_update_req(
  decoder_resource: Decoder(resource),
  decoder_update: Decoder(update),
) -> Decoder(UpdateReq(resource, update)) {
  decode.one_of(
    decoder_update_req_update_req(decoder_resource, decoder_update),
    [],
  )
}

pub fn decoder_update_req_update_req(
  decoder_resource: Decoder(resource),
  decoder_update: Decoder(update),
) -> Decoder(UpdateReq(resource, update)) {
  use id <- decode.field("id", decoder_id(decoder_resource))
  use data <- decode.field("data", decoder_update)
  decode.success(UpdateReq(id:, data:))
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


pub fn encode_params(value: Params(key), encode_key: fn(key) -> Json) -> Json {
  case value {
    Params(..) as value ->
      json.object([
        #("pagination", json.nullable(value.pagination, encode_pagination)),
        #("params", json.array(value.params, encode_param)),
        #("sort", json.array(value.sort, encode_sort(_, encode_key))),
      ])
  }
}

pub fn decoder_params(decoder_key: Decoder(key)) -> Decoder(Params(key)) {
  decode.one_of(decoder_params_params(decoder_key), [])
}

pub fn decoder_params_params(decoder_key: Decoder(key)) -> Decoder(Params(key)) {
  use sort <- decode.field("sort", decode.list(decoder_sort(decoder_key)))
  use params <- decode.field("params", decode.list(decoder_param()))
  use pagination <- decode.optional_field(
    "pagination",
    deriv.none,
    decode.optional(decoder_pagination()),
  )
  decode.success(Params(sort:, params:, pagination:))
}

pub fn encode_sort(value: Sort(key), encode_key: fn(key) -> Json) -> Json {
  case value {
    Sort(..) as value ->
      json.object([
        #("dir", encode_dir(value.dir)),
        #("key", encode_key(value.key)),
      ])
  }
}

pub fn decoder_sort(decoder_key: Decoder(key)) -> Decoder(Sort(key)) {
  decode.one_of(decoder_sort_sort(decoder_key), [])
}

pub fn decoder_sort_sort(decoder_key: Decoder(key)) -> Decoder(Sort(key)) {
  use key <- decode.field("key", decoder_key)
  use dir <- decode.field("dir", decoder_dir())
  decode.success(Sort(key:, dir:))
}

pub fn encode_dir(value: Dir) -> Json {
  case value {
    Asc -> json.object([#("_var", json.string("Asc"))])
    Desc -> json.object([#("_var", json.string("Desc"))])
  }
}

pub fn decoder_dir() -> Decoder(Dir) {
  decode.one_of(decoder_dir_asc(), [decoder_dir_desc()])
}

pub fn decoder_dir_asc() -> Decoder(Dir) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Asc"))
  decode.success(Asc)
}

pub fn decoder_dir_desc() -> Decoder(Dir) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Desc"))
  decode.success(Desc)
}


pub fn encode_param(value: Param) -> Json {
  case value {
    Param(..) as value ->
      json.object([
        #("key", json.string(value.key)),
        #("val", json.string(value.val)),
      ])
  }
}

pub fn decoder_param() -> Decoder(Param) {
  decode.one_of(decoder_param_param(), [])
}

pub fn decoder_param_param() -> Decoder(Param) {
  use key <- decode.field("key", decode.string)
  use val <- decode.field("val", decode.string)
  decode.success(Param(key:, val:))
}


pub fn encode_func(
  value: Func(param, return),
  encode_param: fn(param) -> Json,
  encode_return: fn(return) -> Json,
) -> Json {
  case value {
    Func(..) as value ->
      json.object([#("req", encode_func_req(value.req, encode_param))])
  }
}

pub fn decoder_func(
  decoder_param: Decoder(param),
  decoder_return: Decoder(return),
) -> Decoder(Func(param, return)) {
  decode.one_of(decoder_func_func(decoder_param, decoder_return), [])
}

pub fn decoder_func_func(
  decoder_param: Decoder(param),
  decoder_return: Decoder(return),
) -> Decoder(Func(param, return)) {
  use req <- decode.field("req", decoder_func_req(decoder_param))
  decode.success(Func(req:))
}

pub fn encode_func_req(
  value: FuncReq(param, return),
  encode_param: fn(param) -> Json,
) -> Json {
  case value {
    FuncReq(..) as value -> json.object([#("param", encode_param(value.param))])
  }
}

pub fn decoder_func_req(
  decoder_param: Decoder(param),
) -> Decoder(FuncReq(param, return)) {
  decode.one_of(decoder_func_req_func_req(decoder_param), [])
}

pub fn decoder_func_req_func_req(
  decoder_param: Decoder(param),
) -> Decoder(FuncReq(param, return)) {
  use param <- decode.field("param", decoder_param)
  decode.success(FuncReq(param:))
}