## Working instructions

- Read `design.md` before making implementation changes.
- Treat `design.md` as the source of truth for architecture, behavior, validation, and implementation phases.
- Work incrementally. Implement only the phase explicitly requested by the user.
- Do not proceed into later phases unless explicitly asked.
- Do not redesign architecture or add dependencies/abstractions not justified by `design.md`. If a deviation appears necessary, explain it before implementing it.
- Keep domain logic independent from the HTTP layer.
- Prefer simple, idiomatic Elixir over unnecessary abstractions.
- Before making changes, inspect the existing implementation and briefly state the intended changes and any ambiguity found.
- After making changes:
  - run `mix format --check-formatted`
  - run `mix test`
  - report files changed
  - summarize the implementation
  - report test results and warnings
- Do not create commits or push changes unless explicitly requested.
