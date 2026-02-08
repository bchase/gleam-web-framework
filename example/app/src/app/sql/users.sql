-- name: AuthenticateUser :one
select u.*
from users as u
join user_tokens as ut on u.id = ut.user_id
where ut.hashed_token = @hashed_token;

-- name: InsertUserToken :one
insert into user_tokens ( hashed_token, context, user_id )
values ( @hashed_token, @context, @user_id )
returning *;

-- name: DeleteUserToken :exec
delete from user_tokens
where hashed_token = @hashed_token;

--

-- name: ListUserTokens :many
select * from user_tokens;
