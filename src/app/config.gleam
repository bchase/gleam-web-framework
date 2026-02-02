import app/oauth
import app/oauth/oura

pub type Config {
  Config(
    oura_oauth: oauth.Config,
  )
}

pub fn init() -> Config {
  let oura_oauth = oura.build_config()

  Config(
    oura_oauth:,
  )
}
