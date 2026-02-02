import app/types.{type Config, Config}
import app/oauth/oura

pub fn init() -> Config {
  let oura_oauth = oura.build_config()

  Config(
    oura_oauth:,
  )
}
