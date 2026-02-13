import gleam/io
import gleam/list
import gleam/string
import gleam/result
import gleam/option.{type Option, Some, None}
import lustre
import lustre/attribute as attr
import lustre/server_component
import lustre/effect.{type Effect}
import fpo/types.{type Context, type UserClientInfo, type Fpo}
import fpo/monad/app.{type App, do, pure}
import fpo/lustre.{continue} as _
import gleam/erlang/process.{type Selector}
import lustre/element.{type Element}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist
import gleam/dict.{type Dict}
import fpo/lustre/server_component/socket

pub opaque type ServerComponents(config, pubsub, user, err) {
  ServerComponents(
    components: Dict(List(String), ServerComponent(config, pubsub, user, err)),
  )
}

pub fn new() -> ServerComponents(config, pubsub, user, err) {
  ServerComponents(components: dict.new())
}

pub fn element(
  component component: ServerComponent(config, pubsub, user, err),
  ctx ctx: Context(config, pubsub, user),
) -> Element(msg) {
  element_(component:, ctx:, attrs: [], children: [])
}

pub fn element_(
  component component: ServerComponent(config, pubsub, user, err),
  attrs attrs: List(attr.Attribute(msg)),
  children children: List(Element(msg)),
  ctx ctx: Context(config, pubsub, user),
) -> Element(msg) {
  let route = route(component:, fpo: ctx.fpo)

  server_component.element([
    server_component.route(route),
    ..attrs,
  ], children)
}

fn route(
  component component: ServerComponent(config, pubsub, user, err),
  fpo fpo: Fpo,
) -> String {
  [
    fpo.path_prefix,
    "lsc",
    ..component.route
  ]
  |> string.join("/")
  |> string.append(to: "/", suffix: _)
}

pub opaque type ServerComponent(config, pubsub, user, err) {
  ServerComponent(
    start: fn(Request(mist.Connection), Context(config, pubsub, user)) -> Response(mist.ResponseData),
    route: List(String),
  )
}

pub fn def(
  route route: List(String),
  app app: fn(Context(config, pubsub, user)) -> lustre.App(Context(config, pubsub, user), model, Wrapped(msg)),
) -> ServerComponent(config, pubsub, user, err) {
  ServerComponent(
    route:,
    start: fn(req, ctx) { socket.start(req:, ctx:, app: app(ctx)) },
  )
}

pub fn for(
  components all: ServerComponents(config, pubsub, user, err),
  route route: List(String),
) -> Result(ServerComponent(config, pubsub, user, err), Nil) {
  all.components
  |> dict.get(route)
}

pub fn start(
  component component: ServerComponent(config, pubsub, user, err),
  req req: Request(mist.Connection),
  ctx ctx: Context(config, pubsub, user),
) -> Response(mist.ResponseData) {
  component.start(req, ctx)
}

pub fn register_many(
  components all: ServerComponents(config, pubsub, user, err),
  component new: List(ServerComponent(config, pubsub, user, err)),
) -> Result(ServerComponents(config, pubsub, user, err), List(String)) {
  list.fold_until(new, Ok(all), fn(acc, new) {
    case acc {
      Ok(all) -> list.Continue(register(all, new))
      Error(_) -> list.Stop(acc)
    }
  })
}

pub fn register(
  components all: ServerComponents(config, pubsub, user, err),
  component new: ServerComponent(config, pubsub, user, err),
) -> Result(ServerComponents(config, pubsub, user, err), List(String)) {
  let existing = all.components |> dict.get(new.route)

  use components <-  result.try(
    case existing {
      Ok(_exists) -> Error(new.route)
      Error(Nil) -> Ok(all.components)
    }
  )

  components
  |> dict.insert(new.route, new)
  |> ServerComponents
  |> Ok
}

//

pub fn build_lustre_app(
  init init: fn() -> App(#(model, Effect(msg)), config, pubsub, user, err),
  post_init post_init: Option(fn(model) -> App(#(model, Effect(msg)), config, pubsub, user, err)),
  selectors selectors: fn(model) -> List(App(Selector(msg), config, pubsub, user, err)),
  update update: fn(model, msg) -> App(#(model, Effect(msg)), config, pubsub, user, err),
  view view: fn(model, Option(user), Option(UserClientInfo)) -> Element(msg),
  module module: String,
  ctx ctx: Context(config, pubsub, user),
) -> lustre.App(Context(config, pubsub, user), model, Wrapped(msg)) {
  lustre.application(
    init: wrap_init(init:, module:),
    update: wrap_update(update:, selectors:, post_init:, module:, ctx:),
    view: wrap_view(view:, ctx:),
  )
}

pub type Wrapped(msg) {
  InnerMsg(msg: msg)
  PostInit
}

fn select(
  app app: App(#(model, Effect(msg)), config, pubsub, user, err),
  selectors selectors: fn(model) -> List(App(Selector(msg), config, pubsub, user, err)),
) -> App(#(model, Effect(msg)), config, pubsub, user, err) {
  use #(model, eff) <- do(app)

  model |> continue([
    pure(eff),
    select_eff(selectors:, model:),
  ])
}

fn select_eff(
  selectors selectors: fn(model) -> List(App(Selector(msg), config, pubsub, user, err)),
  model model: model,
) -> App(Effect(msg), config, pubsub, user, err) {
  use selector <- do(
    model
    |> selectors
    |> app.sequence
    |> app.map(list.fold(_, process.new_selector(), process.merge_selector))
  )

  server_component.select(fn(_dispatch, self) {
    selector |> process.select(self)
  })
  |> pure
}

fn log_err(
  app app: App(#(model, Effect(msg)), config, pubsub, user, err),
  module module: String,
  func func: String,
) -> App(#(model, Effect(msg)), config, pubsub, user, err) {
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

  app.from_result(result)
}

fn wrap_init(
  init init: fn() -> App(#(model, Effect(msg)), config, pubsub, user, err),
  module module: String,
) -> fn(Context(config, pubsub, user)) -> #(model, Effect(Wrapped(msg))) {
  fn(ctx) {
    init()
    |> app.map(wrap_effect(model_and_effect: _, wrapper: InnerMsg))
    |> app.map(fn(t) {
      let #(model, eff) = t
      #(model, effect.batch([
        eff,
        effect.from(fn(dispatch) { dispatch(PostInit) }),
      ]))
    })
    |> log_err(module:, func: "wrap_init")
    |> app.run(ctx, Nil)
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
  update update: fn(model, msg) -> App(#(model, Effect(msg)), config, pubsub, user, err),
  selectors selectors: fn(model) -> List(App(Selector(msg), config, pubsub, user, err)),
  post_init post_init: Option(fn(model) -> App(#(model, Effect(msg)), config, pubsub, user, err)),
  module module: String,
  ctx ctx: Context(config, pubsub, user),
) -> fn(model, Wrapped(msg)) -> #(model, Effect(Wrapped(msg))) {
  fn(model, wrapped_msg) {
    case wrapped_msg {
      PostInit -> {
        case post_init {
          None -> pure(#(model, effect.none()))
          Some(post_init) -> post_init(model)
        }
        |> select(selectors:)
      }

      InnerMsg(msg:) -> {
        update(model, msg)
      }
    }
    |> app.map(wrap_effect(model_and_effect: _, wrapper: InnerMsg))
    |> log_err(module:, func: "wrap_update")
    |> app.run(ctx, Nil)
    |> result.unwrap(#(model, effect.none()))
  }
}

fn wrap_view(
  view view: fn(model, Option(user), Option(UserClientInfo)) -> Element(msg),
  ctx ctx: Context(config, pubsub, user),
) -> fn(model) -> Element(Wrapped(msg)) {
  fn(model) {
    view(model, ctx.user, ctx.user_client_info)
    |> element.map(InnerMsg)
  }
}
