typecheck:
	find src/ test/ deps/ -name '*.gleam' | entr -s 'clear; gleam check'

server:
	find src/ test/ deps/ -name '*.gleam' | entr -r -s 'clear; gleam run'

watch-tests:
	find src/ test/ deps/ -name '*.gleam' | entr -s 'clear; gleam test'

parrot:
	DATABASE_URL=postgres://webapp:webapp@127.0.0.1:5432/APP_gleam gleam run -m parrot

squirrel:
	DATABASE_URL=postgres://webapp:webapp@127.0.0.1:5432/APP_gleam gleam run -m squirrel && gleam run -m squirrel_labelled

squirrel-only:
	DATABASE_URL=postgres://webapp:webapp@127.0.0.1:5432/APP_gleam gleam run -m squirrel

squirrel-labelled-only:
	gleam run -m squirrel_labelled

deriv:
	gleam run -m deriv

# make parrot && mv src/APP/sql.gleam src/APP/sql_parrot.gleam && git checkout src/APP/sql.gleam && gleam run -m deriv
