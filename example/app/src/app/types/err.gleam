import sqlight

pub type Err {
  AppErr(err: String)
  SqlightErr(err: sqlight.Error)
}
