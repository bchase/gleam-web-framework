-- name: ListAllMsgs :many
select * from msgs;

-- name: InsertMsg :many
insert into msgs (msg)
values (@msg)
returning *;

-- name: DeleteMsg :exec
delete from msgs
where id = @id;
