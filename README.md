# Job Processor

An Elixir service that validates a collection of tasks, orders them according to
their dependencies, and returns either ordered JSON or a Bash script. Commands are
rendered but never executed.

## Requirements

The project is tested with:

- Erlang/OTP 28.0.1
- Elixir 1.18.4 compiled for OTP 28

The exact asdf versions are pinned in `.tool-versions`.

## Setup

With [asdf](https://asdf-vm.com/) installed:

```sh
asdf install
mix deps.get
```

## Run

```sh
mix run --no-halt
```

The service listens on `http://localhost:4000`.

## JSON response

```sh
curl --request POST http://localhost:4000/jobs \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --data '{
    "tasks": [
      {
        "name": "task-2",
        "command": "cat /tmp/file1",
        "requires": ["task-1"]
      },
      {
        "name": "task-1",
        "command": "touch /tmp/file1"
      }
    ]
  }'
```

Response:

```json
{
  "tasks": [
    {
      "name": "task-1",
      "command": "touch /tmp/file1"
    },
    {
      "name": "task-2",
      "command": "cat /tmp/file1"
    }
  ]
}
```

## Bash response

```sh
curl --request POST http://localhost:4000/jobs \
  --header 'Content-Type: application/json' \
  --header 'Accept: text/plain' \
  --data '{
    "tasks": [
      {
        "name": "task-2",
        "command": "cat /tmp/file1",
        "requires": ["task-1"]
      },
      {
        "name": "task-1",
        "command": "touch /tmp/file1"
      }
    ]
  }'
```

Response:

```bash
#!/usr/bin/env bash
touch /tmp/file1
cat /tmp/file1
```

## Tests

```sh
mix test
```

## Formatting and static analysis

```sh
mix format --check-formatted
mix credo --strict
mix dialyzer
```

CI runs all four quality checks for every push and pull request.

## Development workflow

This solution was developed with Codex in an AI-assisted coding workflow. Architecture
and behavior are captured in [design.md](design.md), with persistent repository-level
agent guidance in [AGENTS.md](AGENTS.md); changes were reviewed and validated using the
quality checks above.

## Design decisions and assumptions

- Task names are unique identifiers; duplicate names are rejected.
- A missing `requires` field defaults to an empty list.
- Dependencies must name tasks in the same request, and duplicate dependencies are
  rejected.
- Cyclic dependency graphs are rejected because they have no valid execution order.
- Tasks that become executable at the same time preserve their original input order.
- Successful JSON responses omit `requires` after the dependencies have been resolved.
- JSON is the default response; Bash is selected with `Accept: text/plain`.
- Shell commands are preserved verbatim, rendered, and never executed.
