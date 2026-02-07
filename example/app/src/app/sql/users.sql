-- name: AuthenticateUser :one
select u.*
from users as u
join user_tokens as ut
where ut.hashed_token = @hashed_token;
