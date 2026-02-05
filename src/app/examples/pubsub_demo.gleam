import gleam/list
import app/monad/app.{type App}
import app/types.{type Context}
import app/lustre/server_component as lsc
import app/lustre.{continue} as _
import gleam/erlang/process.{type Selector}
import gleam/option.{type Option, None}
import lustre
// import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import app/config

const pubsub_channel = "msgs"

//

pub fn component(
  ctx ctx: Context(config, config.PubSub, user),
) -> lustre.App(Context(config, config.PubSub, user), Model, lsc.Wrapped(Msg)) {
  lsc.build_lustre_app(
    module: "app/examples/pubsub_demo",
    init:,
    post_init: None,
    selectors:,
    update:,
    view:,
    ctx:,
  )
}

fn selectors(
  model _model: Model,
) -> List(App(Selector(Msg), config, config.PubSub, user)) {
  [
    app.subscribe(
      to: "msgs",
      in: fn(pubsub: config.PubSub) { pubsub.text },
      wrap: GotPubSubTextMsg,
    )
  ]
}

pub opaque type Model {
  Model(
    nil: Nil,
    msgs: List(String),
  )
}

fn init() -> App(#(Model, Effect(Msg)), config, pubsub, user) {
  Model(
    nil: Nil,
    msgs: [],
  )
  |> continue([])
}

pub opaque type Msg {
  NoOp
  Broadcast(text: String)
  GotPubSubTextMsg(msg: config.TextMsg)
}

fn update(
  model: Model,
  msg: Msg,
) -> App(#(Model, Effect(Msg)), config, config.PubSub, user) {
  case msg {
    NoOp ->
      model
      |> continue([])

    Broadcast(text:) -> {
      use <- app.broadcast(
        to: "msgs",
        in: fn(pubsub: config.PubSub) { pubsub.text },
        msg: config.TextMsg(text:),
      )

      model
      |> continue([
      ])
    }

    GotPubSubTextMsg(msg:) -> {
      Model(..model, msgs: model.msgs |> list.append([msg.text]))
      |> continue([
      ])
    }
  }
}

fn view(
  model: Model,
  _user: Option(user),
  _user_client_info: types.UserClientInfo,
) -> Element(Msg) {
  let text = "hello"

  html.div([], [
    html.h1([], [html.text("PubSub Demo")]),

    html.div([], [
      html.button([
        event.on_click(Broadcast(text:)),
      ], [
        html.text("Broadcast \"" <> text <> "\""),
      ]),
    ]),

    html.h4([], [html.text("Messages:")]),

    html.div([], [
      html.ul([], {
        model.msgs
        |> list.map(fn(msg) {
          html.li([], [
            html.text(msg),
          ])
        })
      }),
    ]),
  ])
}
