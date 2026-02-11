import gleam/option.{type Option}
import gleam/dynamic.{type Dynamic}
import fpo/http/err as fhttp

pub type Err(err) {
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

  SecretKeyBaseLookupFailed

  Err(
    msg: String,
  )

  HttpReqErr(
    err: fhttp.Err,
  )

  Unauthenticated

  AppErr(err: err)
}

pub type Redirect {
  Redirect302
}
