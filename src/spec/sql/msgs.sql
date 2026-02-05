-- name: ListAllMsgs :many
select * from msgs;

-- name: InsertMsg :many
insert into msgs (msg)
values (:msg)
returning *;
