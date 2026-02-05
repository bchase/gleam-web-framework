import gleam/erlang/process
import gleam/otp/static_supervisor
import app/web
//
import app/config

pub fn main() -> Nil {
  let assert Ok(_) =
    config.spec()
    |> web.supervised
    |> static_supervisor.start

  process.sleep_forever()
}
