import gleam/option.{type Option, None}
import fpo/types.{type Session}
import app/types.{type Config} as _

pub type User {
  User
}

pub fn authenticate(
  session _session: Session,
  cfg cfg: Config,
) -> Option(User) {
  None
}
