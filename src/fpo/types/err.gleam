import gleam/option.{type Option}
import gleam/dynamic.{type Dynamic}
import fpo/http/err as fhttp
import pog

pub type Err(err) {
  DbErr(
    err: Dynamic,
  )

  PgErr(
    err: PgErr,
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
  Unauthorized(detail: Option(String))

  AppErr(err: err)
}

pub type PgErr {
  PgQueryErr(err: pog.QueryError)
  PgTxErr(err: pog.TransactionError(String))
}

pub type Redirect {
  Redirect302
}

pub fn pg_err(
  err err: pog.QueryError,
) -> Err(err) {
  PgErr(PgQueryErr(err))
}

pub fn pg_tx_err(
  err err: pog.TransactionError(String),
) -> Err(err) {
  PgErr(PgTxErr(err))
}
