import fpo/oauth
import gleam/result
import gleam/list
import wisp.{type Request, type Response}

pub fn oura_callback(
  req: Request,
  cfg: oauth.Config,
) -> Response {
  let code =
    req
    |> wisp.get_query
    |> list.key_find("code")
    |> result.try(oauth.fetch_access_token(cfg, _))

  case code {
    Ok(oauth) -> {
      // let token = oauth.access_token
      // let client = asana.Client(token:)
      // let resp = asana.get_user(client, "me")

      // case resp {
      //   resp.Success(data: asana_user, ..) -> {
      //     let assert Ok(user_id) =
      //       register_or_log_in_via_asana_oauth(oauth, asana_user, cfg)

      //     case log_in(user_id, req, cfg.db) {
      //       Ok(resp) -> resp

      //       Error(_) -> wisp.redirect("/?error=log_in_error")
      //     }
      //   }

      //   _ -> wisp.redirect("/?error=bad_oauth_code")
      // }

      todo
    }

    Error(_) -> wisp.redirect("/?error=no_oauth_code")
  }
}
