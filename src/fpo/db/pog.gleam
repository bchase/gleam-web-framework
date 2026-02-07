import gleam/dynamic.{type Dynamic}
import fpo/erl
import pog

pub const encode_pog_query_error: fn(pog.QueryError) -> Dynamic = to_dynamic

const to_dynamic: fn(t) -> Dynamic = erl.unsafe_cast
