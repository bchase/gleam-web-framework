import gleam/io
import gleam/list
import gleam/string
import gleam/result
import gleam/option.{type Option, Some, None}
import lustre
import lustre/server_component
import lustre/effect.{type Effect}
import app/types.{type Context, type UserClientInfo}
import app/monad/app.{type App, do, pure, ok}
import app/lustre.{continue} as _
import gleam/erlang/process.{type Selector}
import lustre/element.{type Element}

pub fn build_lustre_app(
  init init: fn() -> App(#(model, Effect(msg)), config, user),
  post_init post_init: Option(fn(model) -> App(#(model, Effect(msg)), config, user)),
  selectors selectors: fn(model) -> List(App(Selector(msg), config, user)),
  update update: fn(model, msg) -> App(#(model, Effect(msg)), config, user),
  view view: fn(model, Option(user), UserClientInfo) -> Element(msg),
  module module: String,
  ctx ctx: Context(config, user),
) -> lustre.App(Context(config, user), model, Wrapped(msg)) {
  lustre.application(
    init: wrap_init(init:, selectors:, module:),
    update: wrap_update(update:, selectors:, post_init:, module:, ctx:),
    view: wrap_view(view:, ctx:),
  )
}

pub type Wrapped(msg) {
  InnerMsg(msg: msg)
  PostInit
}

fn select(
  app app: App(#(model, Effect(msg)), config, user),
  selectors selectors: fn(model) -> List(App(Selector(msg), config, user)),
) -> App(#(model, Effect(msg)), config, user) {
  use #(model, eff) <- do(app)

  use select_eff <- do(build_select_effect(selectors:, model:))

  model |> continue([
    eff,
    select_eff,
  ])
}

fn build_select_effect(
  selectors selectors: fn(model) -> List(App(Selector(msg), config, user)),
  model model: model,
) -> App(Effect(msg), config, user) {
  use selector <- do(
    model
    |> selectors
    |> app.sequence
    |> app.map(list.fold(_, process.new_selector(), process.merge_selector))
  )

  server_component.select(fn(_dispath, self) {
    selector |> process.select(self)
  })
  |> pure
}

fn log_err(
  app app: App(#(model, Effect(msg)), config, user),
  module module: String,
  func func: String,
) -> App(#(model, Effect(msg)), config, user) {
  use result <- app.to_result(app)

  use _log_err_if_any <- do(
    case result {
      Error(err) -> {
        [
          "ERR " <> module <> "." <> func,
          err |> string.inspect,
        ]
        |> string.join("\n")
        |> io.println_error

        pure(Nil)
      }

      Ok(_) ->
        pure(Nil)
    }
  )

  ok(result)
}

fn wrap_init(
  init init: fn() -> App(#(model, Effect(msg)), config, user),
  selectors selectors: fn(model) -> List(App(Selector(msg), config, user)),
  module module: String,
) -> fn(Context(config, user)) -> #(model, Effect(Wrapped(msg))) {
  fn(ctx) {
    init()
    |> select(selectors:)
    |> app.map(wrap_effect(model_and_effect: _, wrapper: InnerMsg))
    |> app.map(fn(t) {
      let #(model, eff) = t
      #(model, effect.batch([
        eff,
        effect.from(fn(dispatch) { dispatch(PostInit) }),
      ]))
    })
    |> log_err(module:, func: "wrap_init")
    |> app.run(ctx)
    |> result.lazy_unwrap(fn() { panic as { "`" <> module <> ".wrap_init` failed" } })
  }
}

fn wrap_effect(
  model_and_effect model_and_effect: #(model, Effect(msg)),
  wrapper wrapper: fn(msg) -> Wrapped(msg),
) -> #(model, Effect(Wrapped(msg))) {
  let #(model, eff) = model_and_effect
  #(model, eff |> effect.map(wrapper))
}

fn wrap_update(
  update update: fn(model, msg) -> App(#(model, Effect(msg)), config, user),
  selectors selectors: fn(model) -> List(App(Selector(msg), config, user)),
  post_init post_init: Option(fn(model) -> App(#(model, Effect(msg)), config, user)),
  module module: String,
  ctx ctx: Context(config, user),
) -> fn(model, Wrapped(msg)) -> #(model, Effect(Wrapped(msg))) {
  fn(model, wrapped_msg) {
    case wrapped_msg {
      PostInit -> {
        case post_init {
          None ->
            pure(#(model, effect.none()))

          Some(post_init) ->
            post_init(model)
            |> select(selectors:)
        }
      }

      InnerMsg(msg:) -> {
        update(model, msg)
      }
    }
    |> app.map(wrap_effect(model_and_effect: _, wrapper: InnerMsg))
    |> log_err(module:, func: "wrap_update")
    |> app.run(ctx)
    |> result.unwrap(#(model, effect.none()))
  }
}

fn wrap_view(
  view view: fn(model, Option(user), UserClientInfo) -> Element(msg),
  ctx ctx: Context(config, user),
) -> fn(model) -> Element(Wrapped(msg)) {
  fn(model) {
    view(model, ctx.user, ctx.user_client_info)
    |> element.map(InnerMsg)
  }
}
