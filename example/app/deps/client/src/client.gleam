import gleam/float
import gleam/int
import plinth/browser/shadow
import plinth/javascript/global
import plinth/browser/document
import plinth/browser/element as dom_element
import lustre/element/keyed
import lustre/event
import gleam/list
import gleam/result
import gleam/dict.{type Dict}
import gleam/string
import gleam/io
import gleam/option.{type Option, Some, None}
import lustre/component
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import gleam/pair
import lustre/effect.{type Effect}
import lustre
import lustre_websocket.{type WebSocketEvent} as ws
import youid/uuid.{type Uuid}
import gleam/javascript/array
import api/client.{type ApiClient, type Api, NotAsked, Loading, Failure, Success}
import api/generic.{type Record, type Action, Created, Updated, Deleted, type Paginated}
import api/id.{type Id}
import client/wrapped_client.{type Conn, type ConnMsg, type ConnectionEvent} as conn

pub fn main() -> Nil {
  register_web_component()
}

const tag_name = "fpo-example-client-component"

fn register_web_component() -> Nil {
  let component = lustre.component(init, update, view, decoders())
  let assert Ok(_) = lustre.register(component, tag_name)

  Nil
}

fn decoders() -> List(component.Option(Msg)) {
  [
    // component.on_attribute_change("", fn(str) { Error(Nil) }),
    // component.on_property_change("", decode.string |> decode.map(msg)),
  ]
}

type Model {
  Model(
    ws_url: String,
    items: client.ApiData(Dict(Id(client.Item), Record(client.Item))),
    item: Option(Record(client.Item)),
    uuid: Uuid,
    //
    client: ApiClient(Api, Model, Msg),
    //
    str: Option(Result(String, client.Err)),
    //
    conn: Conn(Msg),
  )
}

pub fn exp_backoff_delay_ms(
  attempt attempt: Int
) -> Int {
  let attempt =
    case attempt < 1 {
      True -> 1
      False -> attempt
    }

  let base_delay = 1000 // 1s
  let max_delay = 60_000 // 60s

  let exp_delay =
    case int.power(2, int.to_float(attempt)) {
      Error(Nil) ->
        max_delay

      Ok(mul) ->
        base_delay
        |> int.to_float
        |> float.multiply(mul)
        |> float.round()
    }

  exp_delay
  |> int.clamp(min: base_delay, max: max_delay)
  |> int.random
}

type Msg {
  NoOp
  // websockets
  ConnMsg(msg: ConnMsg(Api))
  RecvConnEvent(event: ConnectionEvent)
  // ui
  SendIntToString(num: Int)
  GotItemForm(values: List(#(String, String)))
  SetItem(item: Option(Record(client.Item)))
  DeleteItem(id: Id(client.Item))
  // api resps
  RecvItems(result: Result(Paginated(client.Item), client.Err))
  RecvIntToString(result: Result(String, client.Err))
  RecvItem(action: Action, result: Result(Record(client.Item), client.Err))
}

fn init(_) -> #(Model, Effect(Msg)) {
  let client =
    client.init(
      get_client: fn(model: Model) { model.client },
      set_client: fn(model: Model, client) { Model(..model, client:) },
      get_send: fn(model: Model) {
        case conn.ws(model.conn) {
          None -> None
          Some(conn) -> Some(ws.send(conn, _))
        }
      },
      encode: client.encode_api,
      on_no_conn: fn(_) {
        echo "NO CONN MSG SEND"
        None
      },
    )

  let ws_url = "/ws/api"

  let #(conn, conn_eff) =
    conn.init(
      ws_url:,
      wrap: ConnMsg,
      notify: RecvConnEvent,
    )

  Model(
    ws_url:,
    items: NotAsked,
    item: None,
    uuid: uuid.v7(),
    //
    client:,
    //
    str: None,
    //
    conn: conn,
  )
  |> pair.new(effect.batch([
    conn_eff,
    // effect.from(fn(dispatch) {
    //   dispatch(ReconnectWebsocket(delay: False))
    // })
  ]))
}

fn send_after(
  delay_ms delay_ms: Int,
  msg msg: msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    global.set_timeout(delay_ms, fn() {
      dispatch(msg)
    })
    Nil
  })
}

fn set_focus(
  id id: String,
) -> Effect(Msg) {
  effect.from(fn(_) {
    global.set_timeout(100, fn() {
      {
        use wc <- result.try(document.get_elements_by_tag_name(tag_name) |> array.to_list |> list.first)
        use sr <- result.try(shadow.shadow_root(wc))
        use el <- result.try(shadow.query_selector(sr, "#" <> id))
        Ok(dom_element.focus(el))
      }
      |> result.unwrap(Nil)
    })
    Nil
  })
}

fn update(
  model model: Model,
  msg msg: Msg,
) -> #(Model, Effect(Msg)) {
  // echo msg
  case msg {
    NoOp ->
      pure(model)

    RecvConnEvent(event: conn.Connected(reconnect: False)) -> {
      let #(model, list_items_eff) = model.client.send(model, client.req_list_items(None, msg: RecvItems))
      let #(model, subscribe_items_eff) =
        model.client.send(model, client.req_subscribe_to_items(msg: fn(result) {
          case result {
            Ok(client.ItemsSubMsg(action:, item:)) -> RecvItem(action:, result: Ok(item))
            Error(_) -> NoOp
          }
        }))
      model
      |> eff([
        list_items_eff,
        subscribe_items_eff,
      ])
    }

    RecvConnEvent(event: conn.Disconnected) |
    RecvConnEvent(event: conn.Connected(reconnect: True)) -> {
      pure(model)
    }

    RecvConnEvent(event: conn.WebSocketUrlInvalid) -> {
      panic as { "WebSocket URL invalid" }
    }

    ConnMsg(msg:) -> {
      model
      |> conn.update(
        msg:,
        conn: model.conn,
        get_client: fn(model: Model) { model.client },
        set_conn: fn(model: Model, conn) { Model(..model, conn: conn) },
        wrap: ConnMsg,
      )
    }

    SendIntToString(num:) ->
      model.client.send(model, client.req_int_to_string(num, RecvIntToString))

    RecvIntToString(result:) ->
      pure(Model(..model, str: Some(result)))

    DeleteItem(id: item_id) ->
      model
      |> model.client.send(client.req_delete_items(
        id: item_id,
        confirm: generic.ConfirmDelete,
        msg: fn(t) { RecvItem(action: t.0, result: t.1) },
      ))

    SetItem(item:) ->
      pure(Model(..model, item:))

    RecvItem(action: _, result: Error(err)) -> {
      io.println_error("`RecvItem` err: " <> err |> string.inspect)
      pure(model)
    }

    RecvItem(action: Deleted, result: Ok(item)) -> {
      Model(..model, uuid: uuid.v7(), item: None, items: {
        model.items
        |> map_success(dict.delete(_, item.id))
      })
      |> eff([
        set_focus("item-name"),
      ])
    }

    RecvItem(action: Created, result: Ok(item)) |
    RecvItem(action: Updated, result: Ok(item)) -> {
      Model(..model, uuid: uuid.v7(), item: None, items: {
        case model.items {
          NotAsked | Loading | Failure(err: _) ->
            Success(dict.new())

          Success(items) ->
            Success(items)
        }
        |> map_success(dict.insert(_, item.id, item))
      })
      |> eff([
        set_focus("item-name"),
      ])
    }

    GotItemForm(values:) -> {
      let assert Ok(name) = values |> list.key_find("name")
      let data = client.Item(name:)

      let req =
        case model.item {
          None ->
            client.req_create_items(
              data:,
              msg: fn(t) { RecvItem(action: t.0, result: t.1) },
            )

          Some(item) ->
            client.req_update_items(
              id: item.id,
              data:,
              msg: fn(t) { RecvItem(action: t.0, result: t.1) },
            )
        }

      model.client.send(model, req)
    }

    RecvItems(result:) ->
      case result {
        Ok(generic.Paginated(resources: new, ..)) ->
          pure(Model(..model, items: {
            case model.items {
              NotAsked | Loading | Failure(err: _) -> dict.new()
              Success(data: items) -> items
            }
            |> fn(old) {
              new
              |> list.map(fn(item: Record(client.Item)) {
                #(item.id, item)
              })
              |> dict.from_list
              |> dict.merge(old, _)
              |> Success
            }
          }))

        Error(err) ->
          pure(Model(..model, items: Failure(err)))
      }
  }
}

fn map_success(
  data data: client.ApiData(a),
  apply f: fn(a) -> b,
) -> client.ApiData(b) {
  case data {
    NotAsked -> NotAsked
    Loading -> Loading
    Failure(err:) -> Failure(err:)
    Success(data:) -> Success(data: f(data))
  }
}

fn view(
  model model: Model,
) -> Element(Msg) {
  html.div([], [
    html.div([], [
      html.p([], [
        html.text(string.inspect(model.str)),
      ]),
      html.button([
        event.on_click(SendIntToString(num: 123)),
      ], [
        html.text("Send"),
      ]),
    ]),
    view_items(model:),
    view_item_form(model:),
  ])
}

fn view_item_form(
  model model: Model,
) -> Element(Msg) {
  let item_id: String =
    model.item
    |> option.map(fn(item) { item.id.id })
    |> option.unwrap(model.uuid |> uuid.to_string)

  html.div([], [
    keyed.div([], [#(item_id,
      html.form([
        event.on_submit(GotItemForm),
      ], [
        html.p([], [
          html.label([
            attr.for("item-id"),
          ], [
            html.text("Item ID: "),
          ]),
          html.input([
            attr.disabled(True),
            attr.id("item-id"),
            attr.name("id"),
            attr.type_("text"),
            case model.item {
              Some(item) -> attr.value(item.id.id)
              None -> attr.none()
            },
          ]),
        ]),
        html.p([], [
          html.label([
            attr.for("item-name"),
          ], [
            html.text("Item name: "),
          ]),
          html.input([
            attr.id("item-name"),
            attr.name("name"),
            attr.type_("text"),
            case model.item {
              Some(item) -> attr.value(item.resource.name)
              None -> attr.none()
            },
          ]),
        ]),
        html.button([
          attr.type_("submit"),
        ], [
          html.text("Submit"),
        ]),
      ]),
    )
    ]),
    case model.item {
      None ->
        element.none()

      Some(item) ->
        html.div([], [
          html.button([
            event.on_click(SetItem(None)),
          ], [
            html.text("Cancel"),
          ]),
          html.button([
            event.on_click(DeleteItem(id: item.id)),
          ], [
            html.text("Delete"),
          ]),
        ])
    }
  ])
}

fn view_items(
  model model: Model,
) -> Element(Msg) {
  html.ul([], {
    case model.items {
      NotAsked |
      Loading |
      Failure(err: _) ->
        [html.text(model.items |> string.inspect)]

      Success(data: items) ->
        items
        |> dict.to_list
        |> list.map(pair.second)
        |> list.sort(fn(a: Record(client.Item), b: Record(client.Item)) {
          string.compare(a.resource.name, b.resource.name)
        })
        |> list.map(fn(item) {
          html.li([
            event.on_click(SetItem(item: Some(item))),
          ], [
            html.code([], [
              html.text("(" <> item.id.id <> ") "),
            ]),
            html.span([], [
              html.text(item.resource.name),
            ]),
          ])
        })
    }
  })
}

// lustre helpers

fn pure(
  model model: Model,
) -> #(Model, Effect(Msg)) {
  model |> pair.new(effect.none())
}

fn eff(
  model model: Model,
  effs effs: List(Effect(Msg))
) -> #(Model, Effect(Msg)) {
  model |> pair.new(effect.batch(effs))
}
