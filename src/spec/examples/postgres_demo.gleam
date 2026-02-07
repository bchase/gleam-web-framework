import gleam/string
import gleam/io
import fpo/types/err
import gleam/list
import fpo/monad/app.{type App, do}
import fpo/types.{type Context}
import fpo/lustre/server_component as lsc
import fpo/lustre.{continue, eff} as _
import gleam/erlang/process.{type Selector}
import gleam/option.{type Option, None}
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import spec/config
import spec/domain/msgs/postgres as msgs

pub fn component(
  ctx ctx: Context(config.Config, config.PubSub, user),
) -> lustre.App(Context(config.Config, config.PubSub, user), Model, lsc.Wrapped(Msg)) {
  lsc.build_lustre_app(
    module: "fpo/examples/postgres_demo",
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
) -> List(App(Selector(Msg), config, pubsub, user)) {
  []
}

pub opaque type Model {
  Model(
    nil: Nil,
    msgs: List(msgs.Message),
  )
}

fn init() -> App(#(Model, Effect(Msg)), config.Config, config.PubSub, user) {
  Model(
    nil: Nil,
    msgs: [],
  )
  |> continue([
    msgs.list_all()
    |> eff(
      to_msg: GotMsgs,
      to_err: GotErr(err: _, origin: "postgres_demo.init"),
    )
  ])
}

pub opaque type Msg {
  NoOp

  Submit(
    text: String,
  )

  GotMsgs(
    msgs: List(msgs.Message)
  )

  GotErr(
    err: err.Err,
    origin: String,
  )
}

fn update(
  model: Model,
  msg: Msg,
) -> App(#(Model, Effect(Msg)), config.Config, pubsub, user) {
  case msg {
    NoOp ->
      model
      |> continue([])

    Submit(text:) -> {
      model
      |> continue([
        {
          use _inserted <- do(msgs.insert(text:))
          msgs.list_all()
        }
        |> eff(
          to_msg: GotMsgs,
          to_err: GotErr(err: _, origin: "postgres_demo.update (Submit)"),
        )
      ])
    }

    GotMsgs(msgs:) -> {
      Model(..model, msgs:)
      |> continue([
      ])
    }

    GotErr(err:, origin:) -> {
      { "`" <> origin <> "` " <> string.inspect(err) }
      |> io.println_error

      model
      |> continue([
      ])
    }
  }
}

fn view(
  model: Model,
  _user: Option(user),
  _user_client_info: Option(types.UserClientInfo),
) -> Element(Msg) {
  let text = "hello"

  html.div([], [
    html.h1([], [html.text("PubSub Demo")]),

    html.div([], [
      html.button([
        event.on_click(Submit(text:)),
      ], [
        html.text("Submit \"" <> text <> "\""),
      ]),
    ]),

    html.h4([], [html.text("Messages:")]),

    html.div([], [
      html.ul([], {
        model.msgs
        |> list.map(fn(msg) {
          html.li([], [
            html.text(msg.text),
          ])
        })
      }),
    ]),
  ])
}
