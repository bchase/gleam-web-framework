import app/web
import gleam/erlang/process
import gleam/otp/static_supervisor
import spec

pub fn main() -> Nil {
  let assert Ok(_) =
    spec.spec()
    |> web.supervised
    |> static_supervisor.start

  process.sleep_forever()
}
