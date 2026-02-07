import gleam/option.{type Option}
import gleam/dynamic.{type Dynamic}

pub type Err {
  DbErr(
    err: Dynamic,
  )

  NotFound(
    detail: Option(Dynamic),
  )

  Err(
    msg: String,
  )
}
