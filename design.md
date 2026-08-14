# Job Processor - Technical Design

## Purpose and scope

The service accepts a job containing named shell-command tasks, validates their
dependencies, and returns the tasks in a valid execution order. The ordered job can
be represented as JSON or as a Bash script.

The service renders commands but never executes them. Persistence, authentication,
background processing, retries, distributed scheduling, and command sandboxing are
outside the scope of this challenge.

## Architecture

The project is a small OTP application built with Plug, Bandit, and Jason. Bandit is
supervised by `JobProcessor.Application` and serves `JobProcessorWeb.Router` on port
4000.

```text
HTTP request
    |
    v
JobProcessorWeb.Router
    |
    +-- JobProcessor.TaskParser
    |       external maps -> validated JobProcessor.Task structs
    |
    +-- JobProcessor.TaskSorter
    |       validated tasks -> dependency-respecting order
    |
    +-- JobProcessor.BashRenderer
            ordered tasks -> Bash text
```

Module responsibilities:

- `JobProcessor.Task` and `JobProcessor.Error` define domain values.
- `JobProcessor.TaskParser` owns request-shape and dependency validation.
- `JobProcessor.TaskSorter` implements deterministic topological sorting.
- `JobProcessor.BashRenderer` renders commands without interpreting or modifying
  them.
- `JobProcessorWeb.Router` owns HTTP parsing, content negotiation, response encoding,
  and status-code mapping.

The parser, sorter, and renderer are pure domain modules with no dependency on Plug
or Bandit.

## API contract

The service exposes:

```http
POST /jobs
Content-Type: application/json
```

Request body:

```json
{
  "tasks": [
    {
      "name": "task-1",
      "command": "touch /tmp/file1"
    },
    {
      "name": "task-2",
      "command": "cat /tmp/file1",
      "requires": ["task-1"]
    }
  ]
}
```

### JSON representation

JSON is returned when `Accept` is absent, accepts `application/json`, or contains a
matching wildcard. Successful JSON output intentionally omits `requires` because the
dependencies have already been resolved into an execution order.

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

### Bash representation

`Accept: text/plain` selects Bash output with content type
`text/plain; charset=utf-8`.

```bash
#!/usr/bin/env bash
touch /tmp/file1
cat /tmp/file1
```

The script always has the `#!/usr/bin/env bash` shebang and a final newline. An empty
job still produces a valid script containing the shebang.

### Accept negotiation

Supported media ranges are `application/json`, `text/plain`, and their applicable
wildcards. The implementation intentionally evaluates media ranges in client-provided
order and selects the first supported representation. It does not implement full
`q`-value prioritization; this is a deliberate scope trade-off for the small service.
If no representation is supported, the service returns `406 Not Acceptable`.

Unmatched routes return `404 Not Found`.

## Validation decisions

`JobProcessor.TaskParser` converts external JSON maps into `%JobProcessor.Task{}`
structs only after validation.

- The top-level payload must contain `tasks`.
- `tasks` must be a list; an empty list is valid.
- Every task must contain non-empty string `name` and `command` fields.
- Missing `requires` defaults to `[]`.
- `requires`, when present, must be a list of strings.
- Task names must be unique within the request.
- A task may not list the same dependency more than once.
- Every dependency must reference a task name in the same request.
- Input is validated strictly; values are not automatically converted or duplicate dependencies silently removed.

Expected invalid input returns explicit `%JobProcessor.Error{}` values rather than
raising exceptions. Self-dependencies are handled consistently with other cycles by
the sorter.

## Error semantics

Domain errors are returned as JSON:

```json
{
  "error": {
    "code": "unknown_dependency",
    "message": "Task 'task-2' requires unknown task 'task-99'"
  }
}
```

| Condition | Code | HTTP status |
|---|---|---:|
| Malformed JSON or invalid top-level shape | `invalid_request` | `400` |
| Invalid task fields or dependency shape | `invalid_task` | `400` |
| Duplicate task name | `duplicate_task` | `400` |
| Duplicate dependency | `duplicate_dependency` | `400` |
| Unknown dependency | `unknown_dependency` | `400` |
| Cyclic dependency graph | `cyclic_dependency` | `422` |
| Unsupported response representation | n/a | `406` |

A cycle receives `422 Unprocessable Entity` because the request can be structurally
valid while describing a graph with no execution order.

## Deterministic topological sorting

`JobProcessor.TaskSorter` implements Kahn's algorithm over validated tasks.

It builds:

- a task lookup by name;
- the original request index for every task;
- an incoming dependency count for every task;
- reverse adjacency lists from each task to its dependants; and
- an ordered set of currently executable tasks.

The sorter repeatedly removes the next ready task, appends it to the result, and
decrements the incoming count of its dependants. A dependant enters the ready set when
its count reaches zero. If the ready set becomes empty before all tasks are processed,
the remaining graph contains a cycle.

### Original-order tie-breaking and `:gb_sets`

Topological order is not unique. Among tasks that are executable at the same time,
the service selects the task that appeared earliest in the original request.

The ready set is an Erlang `:gb_sets` tree containing
`{original_index, task_name}` tuples. Erlang tuple ordering makes the original index
the primary key, while the validated unique name identifies the task. This avoids
depending on map iteration order and also handles tasks that become ready later but
appeared earlier in the request.

The ordered tree is a small, intentional complexity trade-off for explicit and stable
tie-breaking. Each task is inserted into and removed from the ready set at most once.

### Complexity

- Graph construction: `O(V + E)`
- Ordered ready-set insertion/removal: `O(log V)` per operation
- Overall sorter time: approximately `O(E + V log V)`
- Space: `O(V + E)`

`V` is the number of tasks and `E` is the number of dependency edges.

The sorter expects validated tasks. Bang functions used for task, index, and dependency
count lookups assert invariants established by the parser and graph construction; an
invariant failure is a programming error rather than expected user input.

## Bash rendering

`JobProcessor.BashRenderer` is a pure transformation over already ordered tasks.
Commands are emitted verbatim in the supplied order after the shebang.

The renderer does not parse shell syntax, normalize quoting, escape content, validate
commands, or execute them. If command execution were added to a real system, it would
require a separate security design for isolation, timeouts, resource limits, and
filesystem and network access.

## Assumptions and trade-offs

- Task names are request-local identifiers.
- Dependencies must refer to tasks in the same request.
- Independent ready tasks preserve original request order.
- Cycles are reported without attempting to identify the exact cycle path.
- JSON is the default representation; Bash is requested with `Accept: text/plain`.
- Commands are trusted only as opaque text and are never executed.
- The HTTP layer contains representation and status mapping only; validation and graph
  logic remain in domain modules.
- The solution favors explicit behavior and small focused modules over generic
  frameworks or additional process abstractions.
