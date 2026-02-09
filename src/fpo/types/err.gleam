import gleam/option.{type Option}
import gleam/dynamic.{type Dynamic}

pub type Err {
  DbErr(
    err: Dynamic,
  )

  NotFound(
    detail: Option(Dynamic),
  )

  RedirectTo(
    location: String,
    using: Redirect,
    flash: Option(String),
    err: Option(String),
  )

  Err(
    msg: String,
  )
}

pub type Redirect {
  Redirect302
}
