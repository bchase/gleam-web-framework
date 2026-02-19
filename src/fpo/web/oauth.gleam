import gleam/http/response.{type Response}
import gleam/uri.{type Uri}
import wisp
import gleam/option.{None}
import fpo/types/err
import gleam/dict
import fpo/monad/app
import fpo/types/spec

pub fn redirect(
  provider provider: String,
  redirects redirects: List(#(String, app.App(Uri, config, pubsub, user, err))),
  err handle: fn(err.Err(err)) -> Response(wisp.Body),
) -> spec.Handler(config, pubsub, user, err) {
  spec.Wisp(fn(_req, ctx) {
    {
      app.do_ok(
        redirects
        |> dict.from_list
        |> dict.get(provider)
        |> app.pure,
        fn(_) { err.NotFound(None) },
      fn(build_uri) {

        build_uri
      })
    }
    |> app.run(ctx, Nil)
    |> fn(result) {
      case result {
        Ok(uri) ->
          wisp.response(302)
          |> wisp.set_header("location", uri |> uri.to_string)

        Error(err) ->
          handle(err)
      }
    }
  })
}
