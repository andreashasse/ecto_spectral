# ecto_spectral

An `Ecto.ParameterizedType` that stores [Spectral](https://github.com/andreashasse/spectral)-typed
values in Postgres `jsonb` columns. Sibling of `phoenix_spectral`; both wrap `spectral`, which
wraps the Erlang `spectra`.

## Working here

- The test suite needs a real Postgres instance. `make db` starts one, `make ci` runs
  everything CI runs. `make db` publishes on `PGPORT`, so set it if 5432 is taken.
- Regression tests for anything involving what the column actually holds belong in
  `test/ecto_spectral/postgres_test.exs`, not the unit suite. A claim about `jsonb` that is
  not checked against `jsonb` is not checked.
- A new column needs a new migration file. Never edit an existing one: the `test` alias
  migrates but does not drop, so an in-place edit never reaches a database that already ran it.
- Test-only configuration lives in `config/test.exs`.

## Writing the docs

The callbacks are the hard part of this library, and a few things make explanations of them
go wrong.

- The README and the moduledoc say what a user sees and has to do. How the library decides,
  such as the shape rule in `cast/2` or why `nil` reaches the callbacks, goes in comments
  beside the code.
- Say which direction a callback runs. `cast/2` and `load/3` decode, `dump/3` encodes.
  "Cast" reads like the write path and is not.
- Show the shapes before explaining the rule. A rule about which values `cast/2` accepts is
  unreadable without the two or three example values it is about.

Claims about Postgres behaviour need a test that demonstrates them. Several confident
sentences here turned out to be wrong; each one now has a test next to it.
