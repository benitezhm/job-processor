# Repository instructions

- Read `design.md` before architectural or behavioral changes.
- Keep the solution proportionate, simple, and idiomatic Elixir.
- Keep domain logic independent from the HTTP layer.
- Explain any necessary deviation from `design.md` before implementing it.
- Avoid dependencies and abstractions that are not justified by the project scope.
- After implementation changes, run:
  - `mix format --check-formatted`
  - `mix test`
  - `mix credo --strict`
  - `mix dialyzer`
- Do not commit or push changes unless explicitly requested.
