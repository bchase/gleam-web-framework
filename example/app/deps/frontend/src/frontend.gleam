import fpo/api/ws/client.{type ApiData, type Err as ApiErr, type ConnectionEvent, NotAsked, Loading, Failure, Success, Connected, Disconnected, WebSocketUrlInvalid, zero_api_client, map_success, success_or} as _
import fpo/api/ws/types.{type Id, type Record, type Action, Created, Updated, Deleted, type Paginated}
import fpo/api/js/ws/client.{type Client}
import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/pair
import gleam/result
import gleam/string
import lustre
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import plinth/browser/document
import plinth/browser/element as dom_element
import plinth/javascript/global
import shared/api.{type Api}
import youid/uuid.{type Uuid}

const lustre_app_target_selector = "body"

pub fn main() -> Nil {
  let assert Ok(_) =
    lustre.application(init, update, view)
    |> lustre.start(onto: lustre_app_target_selector, with: Nil)

  Nil
}

type Model {
  Model(
    items: ApiData(Dict(Id(api.Item), Record(api.Item))),
    item: Option(Record(api.Item)),
    uuid: Uuid,
    //
    client: Client(Api, Model, Msg),
    //
    str: Option(Result(String, ApiErr)),
  )
}

type Msg {
  NoOp
  // websockets
  ClientMsg(msg: client.Msg)
  RecvWebSocketConnEvent(event: ConnectionEvent)
  // ui
  SendIntToString(num: Int)
  GotItemForm(values: List(#(String, String)))
  SetItem(item: Option(Record(api.Item)))
  DeleteItem(id: Id(api.Item))
  // api resps
  RecvItems(result: Result(Paginated(api.Item), ApiErr))
  RecvIntToString(result: Result(String, ApiErr))
  RecvItem(action: Action, result: Result(Record(api.Item), ApiErr))
}

fn init(_) -> #(Model, Effect(Msg)) {
  let ws_url = "/ws/api"

  Model(
    uuid: uuid.v7(),
    //
    client: zero_api_client(zero: NoOp),
    //
    str: None,
    items: NotAsked,
    item: None,
  )
  |> client.init(
    ws_url:,
    get_client: fn(model: Model) { model.client },
    set_client: fn(model: Model, client) { Model(..model, client:) },
    wrap: ClientMsg,
    encode: api.encode_api,
    on_no_conn: fn(_) {
      echo "NO CONN MSG SEND"
      None
    },
    notify: fn(event) { Some(RecvWebSocketConnEvent(event:)) },
  )
}

fn update(
  model model: Model,
  msg msg: Msg,
) -> #(Model, Effect(Msg)) {
  // echo msg
  case msg {
    NoOp ->
      pure(model)

    RecvWebSocketConnEvent(event:) -> {
      case event |> echo {
        WebSocketUrlInvalid ->
          panic as "invalid websocket url"

        Disconnected ->
          pure(model)

        Connected(reconnect: _) -> {
          let #(model, list_items_eff) = model |> model.client.send(api.req_list_items(None, RecvItems))
          let #(model, sub_items_eff) = model |> model.client.send(api.req_subscribe_to_items(fn(msg) {
            RecvItem(action: msg.action, result: Ok(msg.item))
          }))
          // let #(model, sub_items_eff) = model |> model.client.send(api.req_subscribe_to_items(fn(result) {
          //   case result {
          //     Ok(api.ItemsSubMsg(action:, item:)) ->
          //       RecvItem(action:, result: Ok(item))

          //     Error(err) -> {
          //       io.println_error("Failed handle items sub msg: " <> string.inspect(err))
          //       NoOp
          //     }
          //   }
          // }))

          model
          |> pair.new(effect.batch([
            list_items_eff,
            sub_items_eff,
          ]))
        }
      }
    }

    ClientMsg(msg:) ->
      client.update(model:, client: model.client, msg:)

    SendIntToString(num:) ->
      model.client.send(model, api.req_int_to_string(num, RecvIntToString))

    RecvIntToString(result:) ->
      pure(Model(..model, str: Some(result)))

    DeleteItem(id: item_id) ->
      model
      |> model.client.send(api.req_delete_items(
        id: item_id,
        confirm: types.ConfirmDelete,
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
        model.items
        |> success_or(default: dict.new())
        |> map_success(dict.insert(_, item.id, item))
      })
      |> eff([
        set_focus("item-name"),
      ])
    }

    GotItemForm(values:) -> {
      let assert Ok(name) = values |> list.key_find("name")
      let data = api.Item(name:)

      let req =
        case model.item {
          None ->
            api.req_create_items(
              data:,
              msg: fn(t) { RecvItem(action: t.0, result: t.1) },
            )

          Some(item) ->
            api.req_update_items(
              id: item.id,
              data:,
              msg: fn(t) { RecvItem(action: t.0, result: t.1) },
            )
        }

      model.client.send(model, req)
    }

    RecvItems(result:) ->
      case result {
        Ok(types.Paginated(resources: new, ..)) ->
          pure(Model(..model, items: {
            case model.items {
              NotAsked | Loading | Failure(err: _) -> dict.new()
              Success(data: items) -> items
            }
            |> fn(old) {
              new
              |> list.map(fn(item: Record(api.Item)) {
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
        |> list.sort(fn(a: Record(api.Item), b: Record(api.Item)) {
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

// dom helpers

fn set_focus(
  id id: String,
) -> Effect(Msg) {
  effect.from(fn(_) {
    global.set_timeout(100, fn() {
      {
        // use wc <- result.try(document.get_elements_by_tag_name(tag_name) |> array.to_list |> list.first)
        // use sr <- result.try(shadow.shadow_root(wc))
        // use el <- result.try(shadow.query_selector(sr, "#" <> id))
        use el <- result.try(document.query_selector("#" <> id))
        Ok(dom_element.focus(el))
      }
      |> result.unwrap(Nil)
    })
    Nil
  })
}

// import lustre/component
// import plinth/browser/shadow
// import gleam/javascript/array
// const tag_name = "fpo-example-client-component"
// fn register_web_component() -> Nil {
//   let component = lustre.component(init, update, view, decoders())
//   let assert Ok(_) = lustre.register(component, tag_name)
//   Nil
// }
// fn decoders() -> List(component.Option(Msg)) {
//   [
//     // component.on_attribute_change("", fn(str) { Error(Nil) }),
//     // component.on_property_change("", decode.string |> decode.map(msg)),
//   ]
// }
// pub fn main() -> Nil {
//   register_web_component()
//   Nil
// }
