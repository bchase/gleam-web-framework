import gleam/dynamic.{type Dynamic}
import pog

pub const encode_pog_query_error: fn(pog.QueryError) -> Dynamic = to_dynamic

@external(erlang, "app_erl_ffi", "unsafe_cast")
pub fn to_dynamic(x: a) -> Dynamic
