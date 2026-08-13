# Job Processor — Design Specification

## 1. Purpose

This document defines the implementation design for the CraftingSoftware Elixir coding challenge.

The service accepts a job represented as a collection of tasks. Each task has:

- a unique `name`
- a shell `command`
- an optional list of task names in `requires`

Dependencies determine execution order. The service must return the tasks in a valid dependency-respecting order and must also be able to return the ordered commands as a Bash script.

The service **does not execute shell commands**. It validates, orders, and renders them.

---

## 2. Goals

The implementation should be:

- correct
- small and easy to review
- idiomatic Elixir
- deterministic
- well tested
- explicit about invalid input
- easy to run locally
- easy to evaluate from the repository

The implementation should demonstrate appropriate engineering judgment without adding unnecessary infrastructure.

---

## 3. Non-goals

The following are intentionally out of scope:

- executing shell commands
- persistence or databases
- background job processing
- authentication or authorization
- user accounts
- distributed job scheduling
- retries
- process isolation or sandboxing
- Docker orchestration
- Kubernetes
- WebSockets
- Ecto
- Oban
- LiveView
- unnecessary GenServers

If command execution were required in a real system, it would need a separate security design covering isolation, timeouts, resource limits, filesystem/network access, and subprocess management.

---

## 4. Technology Stack

Use:

- Elixir
- Plug
- Bandit
- Jason
- ExUnit

Do not use Phoenix unless implementation constraints discovered later provide a strong reason to change this decision.

The service should be a normal OTP application, with Bandit supervised by the application supervisor.

Conceptual structure:

```text
Application
    |
    +-- Bandit
          |
          +-- Router
                |
                +-- TaskParser
                +-- TaskSorter
                +-- BashRenderer
```

The graph-sorting logic must remain pure Elixir and independent of HTTP.

---

## 5. Repository Name

Preferred repository name:

```text
job-processor
```

The README may state that it is an implementation of the CraftingSoftware Elixir coding challenge.

---

## 6. Proposed Project Structure

```text
lib/
├── job_processor.ex
├── job_processor/
│   ├── application.ex
│   ├── error.ex
│   ├── task.ex
│   ├── task_parser.ex
│   ├── task_sorter.ex
│   └── bash_renderer.ex
│
└── job_processor_web/
    └── router.ex

test/
├── job_processor/
│   ├── task_parser_test.exs
│   ├── task_sorter_test.exs
│   └── bash_renderer_test.exs
│
└── job_processor_web/
    └── router_test.exs
```

A small deviation from this layout is acceptable if it improves clarity, but domain logic must not be embedded in the router.

---

## 7. Domain Model

Represent each validated task as a domain struct.

Example:

```elixir
%JobProcessor.Task{
  name: "task-2",
  command: "cat /tmp/file1",
  requires: ["task-3"]
}
```

Suggested definition:

```elixir
defmodule JobProcessor.Task do
  @enforce_keys [:name, :command]
  defstruct [:name, :command, requires: []]

  @type t :: %__MODULE__{
          name: String.t(),
          command: String.t(),
          requires: [String.t()]
        }
end
```

The HTTP layer should convert external JSON maps into domain structs before invoking business logic.

Boundary:

```text
JSON request
    ↓
TaskParser
    ↓
domain structs
    ↓
TaskSorter
    ↓
ordered domain structs
    ↓
JSON or Bash representation
```

---

## 8. Request Contract

Expose one endpoint:

```http
POST /jobs
```

Request content type:

```http
Content-Type: application/json
```

Expected request shape:

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

### `requires`

`requires` is optional.

If omitted:

```elixir
requires: []
```

No coercion should be performed.

For example, this is invalid:

```json
{
  "name": "task-2",
  "command": "echo hello",
  "requires": "task-1"
}
```

The correct shape is:

```json
{
  "name": "task-2",
  "command": "echo hello",
  "requires": ["task-1"]
}
```

---

## 9. Response Negotiation

Use the HTTP `Accept` header to choose the response representation.

### JSON

Request:

```http
POST /jobs
Content-Type: application/json
Accept: application/json
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

The successful ordered JSON response intentionally omits `requires`, following the challenge example. Once the order has been resolved, dependencies are no longer needed in the execution representation.

### Bash

Request:

```http
POST /jobs
Content-Type: application/json
Accept: text/plain
```

Response:

```bash
#!/usr/bin/env bash
touch /tmp/file1
cat /tmp/file1
```

Use:

```http
Content-Type: text/plain; charset=utf-8
```

### Default

If `Accept` is absent or effectively accepts any representation (`*/*`), default to JSON.

### Unsupported representation

An explicit unsupported representation, for example:

```http
Accept: application/xml
```

should return:

```http
406 Not Acceptable
```

---

## 10. Validation Rules

Validation should be strict enough to expose malformed jobs instead of silently normalizing them.

### 10.1 Top-level request

The payload must contain:

```json
{
  "tasks": [...]
}
```

`tasks` must be an array.

An empty array is valid.

```json
{
  "tasks": []
}
```

returns:

```json
{
  "tasks": []
}
```

### 10.2 Required task fields

Each task must contain:

- `name`
- `command`

Both must be non-empty strings.

Reject:

```json
{
  "name": "",
  "command": "echo hello"
}
```

and:

```json
{
  "name": "task-1",
  "command": ""
}
```

### 10.3 Task names are unique

Task names act as identifiers and must be unique within the request.

Reject duplicate task names.

### 10.4 Dependency shape

If `requires` is present:

- it must be an array
- every entry must be a string
- every referenced task must exist in the same request

### 10.5 Duplicate dependencies

Reject duplicate dependencies.

Example:

```json
{
  "name": "task-b",
  "command": "echo B",
  "requires": ["task-a", "task-a"]
}
```

should be invalid rather than silently deduplicated.

### 10.6 Unknown dependencies

Reject tasks that reference names that are not present in the same request.

### 10.7 Self-dependencies

A self-dependency is invalid because it creates a cycle.

It may be rejected explicitly during validation or detected by cycle detection. Prefer whichever keeps the implementation simpler and the error behavior consistent.

### 10.8 Cycles

Any cyclic dependency graph is invalid.

Example:

```text
A requires B
B requires C
C requires A
```

No execution order exists.

---

## 11. Error Model

Use domain error values rather than exceptions for expected invalid input.

Suggested type:

```elixir
defmodule JobProcessor.Error do
  @enforce_keys [:code, :message]
  defstruct [:code, :message]
end
```

Example:

```elixir
%JobProcessor.Error{
  code: :unknown_dependency,
  message: "Task 'task-2' requires unknown task 'task-99'"
}
```

The HTTP layer maps domain errors into status codes and JSON.

Standard response shape:

```json
{
  "error": {
    "code": "unknown_dependency",
    "message": "Task 'task-2' requires unknown task 'task-99'"
  }
}
```

Expected error codes:

```text
invalid_request
invalid_task
duplicate_task
duplicate_dependency
unknown_dependency
cyclic_dependency
```

Avoid building a generic validation framework. Keep errors explicit and local to this problem.

---

## 12. HTTP Status Codes

Use:

| Condition | Status |
|---|---:|
| Success | `200 OK` |
| Malformed JSON | `400 Bad Request` |
| Invalid request structure | `400 Bad Request` |
| Invalid task | `400 Bad Request` |
| Duplicate task | `400 Bad Request` |
| Duplicate dependency | `400 Bad Request` |
| Unknown dependency | `400 Bad Request` |
| Cyclic dependency graph | `422 Unprocessable Entity` |
| Unsupported explicit `Accept` type | `406 Not Acceptable` |

The distinction for cycles is intentional: the request can be structurally valid while describing a graph that cannot be resolved into an execution order.

---

## 13. Task Parsing

`TaskParser` should be responsible for:

1. validating the external request structure
2. validating task fields
3. applying the default `requires: []`
4. checking duplicate task names
5. validating dependency list shape
6. checking duplicate dependencies
7. checking unknown dependencies
8. converting valid external maps into `%JobProcessor.Task{}` structs

Suggested interface:

```elixir
@spec parse(map()) ::
        {:ok, [JobProcessor.Task.t()]}
        | {:error, JobProcessor.Error.t()}

def parse(params)
```

Desired pipeline:

```elixir
with {:ok, tasks} <- TaskParser.parse(params),
     {:ok, ordered_tasks} <- TaskSorter.sort(tasks) do
  ...
end
```

---

## 14. Sorting Algorithm

Implement Kahn's topological sorting algorithm directly.

Do not use a GenServer.

Do not rely on `Map` iteration order.

Core data structures:

```text
task_by_name
dependency_count
dependants
ready queue
result
original_index
```

Algorithm:

1. Build a lookup from task name to task.
2. Record the original request index of every task.
3. Calculate the incoming dependency count for every task.
4. Build the reverse adjacency map: for each task, which tasks depend on it.
5. Initialize the ready queue with tasks whose dependency count is zero.
6. Repeatedly:
   - remove the next ready task
   - append it to the result
   - decrement dependency counts for its dependants
   - when a dependant reaches zero, insert it into the ready queue according to deterministic ordering rules
7. If the number of produced tasks equals the number of input tasks, return the result.
8. Otherwise return `cyclic_dependency`.

Complexity target:

```text
Time:  O(V + E)
Space: O(V + E)
```

where:

- `V` is the number of tasks
- `E` is the number of dependency edges

---

## 15. Deterministic Ordering

Topological order is not necessarily unique.

The service should use the following tie-breaking rule:

> Among tasks that are simultaneously executable, preserve their original request order.

Example:

Input:

```text
C
A
B
```

with no dependencies should return:

```text
C
A
B
```

Example:

```text
A
├── B
└── C
```

If the request order is:

```text
A
B
C
```

then the output should remain:

```text
A
B
C
```

Do not depend on map/hash iteration order to achieve this.

The implementation should explicitly preserve original indexes.

---

## 16. Cycle Reporting

The sorter only needs to determine whether a cycle exists.

It does not need to discover or return the exact cycle path.

Return:

```json
{
  "error": {
    "code": "cyclic_dependency",
    "message": "Task dependencies contain a cycle"
  }
}
```

Do not add DFS cycle-path extraction unless there is a compelling implementation reason later.

---

## 17. Bash Rendering

`BashRenderer` should be a pure function.

Suggested interface:

```elixir
@spec render([JobProcessor.Task.t()]) :: String.t()

def render(tasks)
```

Output format:

```bash
#!/usr/bin/env bash
<command 1>
<command 2>
...
```

Include a final trailing newline.

Commands must be emitted **verbatim**.

Do not:

- normalize quotes
- escape commands
- parse Bash syntax
- validate shell syntax
- modify whitespace inside commands
- execute commands

If the input contains:

```json
{
  "command": "echo 'Hello World!' > /tmp/file1"
}
```

the Bash output should contain exactly:

```bash
echo 'Hello World!' > /tmp/file1
```

---

## 18. HTTP Layer Responsibilities

The router should be thin.

It should:

1. receive the request
2. decode JSON through Plug/Jason
3. determine requested representation
4. call `TaskParser`
5. call `TaskSorter`
6. render JSON or Bash
7. translate domain errors to HTTP responses

It should not:

- implement graph logic
- perform dependency validation itself
- mutate commands
- contain task-ordering algorithms

---

## 19. Testing Strategy

Tests should be layered rather than duplicating every scenario through HTTP.

### 19.1 Task parser tests

Cover:

- valid task without `requires`
- valid task with `requires`
- empty task list
- missing `tasks`
- non-array `tasks`
- missing `name`
- missing `command`
- empty `name`
- empty `command`
- invalid `requires` type
- non-string dependency
- duplicate task names
- duplicate dependencies
- unknown dependency

### 19.2 Task sorter tests

Cover:

- challenge example
- one task
- empty list
- linear chain
- independent tasks
- branching dependencies
- converging dependencies
- direct cycle
- indirect cycle
- self-cycle
- deterministic ordering

Representative graph:

```text
       A
      / \
     B   C
      \ /
       D
```

Dependencies:

```text
B requires A
C requires A
D requires B, C
```

For graph correctness tests where multiple orders are valid, assert dependency invariants rather than unnecessarily requiring one exact sequence.

For example:

```text
A before B
A before C
B before D
C before D
```

Test deterministic tie-breaking separately.

### 19.3 Bash renderer tests

Cover:

- shebang
- correct ordered commands
- commands preserved verbatim
- trailing newline
- empty task list

For an empty list, expected output should still be a valid script:

```bash
#!/usr/bin/env bash
```

with a trailing newline.

### 19.4 HTTP integration tests

Cover only the external API contract:

- JSON request -> JSON response
- JSON request -> Bash response
- default response when `Accept` is absent
- malformed/invalid request -> JSON error
- cycle -> `422`
- unsupported `Accept` -> `406`

Do not duplicate every graph case at the HTTP layer.

---

## 20. Quality Tooling

Required:

```bash
mix format --check-formatted
mix test
```

Do not initially add:

- Credo
- Dialyzer
- StreamData

They may be reconsidered after the core solution is complete, but only if they add clear review value without increasing noise.

---

## 21. Runtime Versions

Pin compatible Elixir/Erlang versions.

Prefer:

```text
.tool-versions
```

Choose current stable compatible versions at implementation time rather than hard-coding unverified versions in this design document.

The README must state the tested versions.

---

## 22. Docker

Docker is not required.

Primary execution path should remain:

```bash
mix deps.get
mix test
mix run --no-halt
```

Do not add Docker unless a concrete need emerges.

---

## 23. CI

Add a small GitHub Actions workflow.

It should:

1. check out the repository
2. install/setup the pinned Erlang/Elixir versions
3. fetch dependencies
4. run formatting validation
5. run tests

Minimum checks:

```bash
mix format --check-formatted
mix test
```

Do not add deployment or unnecessary CI complexity.

---

## 24. README Requirements

The README is part of the deliverable and should be concise but complete.

Include:

### Overview

Explain what the service does.

### Requirements

Document tested Erlang and Elixir versions.

### Setup

```bash
mix deps.get
```

### Run

Document the exact command and listening port.

### JSON example

Provide a complete `curl` request.

### Bash example

Provide a complete `curl` request using:

```http
Accept: text/plain
```

### Tests

```bash
mix test
```

### Formatting

```bash
mix format --check-formatted
```

### Design decisions / assumptions

Document:

- task names are unique identifiers
- `requires` defaults to `[]`
- dependencies must reference tasks in the same request
- duplicate names are rejected
- duplicate dependencies are rejected
- cycles are rejected
- independent executable tasks preserve input order
- shell commands are preserved verbatim
- commands are rendered but never executed
- JSON is the default representation
- Bash is requested through the `Accept` header

---

## 25. Git Strategy

Prefer small, meaningful commits.

Suggested progression:

```text
Initialize Elixir job processor

Add task parsing and validation

Implement deterministic topological sorting

Add Bash rendering

Expose HTTP job processing API

Handle API and graph errors

Add integration tests

Add CI and documentation
```

Do not artificially create one commit per file, and do not collapse the entire solution into one large implementation commit.

---

## 26. Codex Implementation Workflow

Codex should implement this design incrementally.

It should not independently redesign the architecture unless it discovers a concrete technical problem. Any proposed deviation from this document should be explained before being implemented.

### Phase 1 — Project initialization

- initialize the Mix OTP application
- add Plug, Bandit, and Jason
- configure supervision
- add domain structs
- do not implement HTTP behavior yet

Review before continuing.

### Phase 2 — Parsing and validation

Implement:

- `Task`
- `Error`
- `TaskParser`
- parser unit tests

Review before continuing.

### Phase 3 — Topological sorting

Implement:

- deterministic Kahn topological sort
- cycle detection
- sorter unit tests

Review before continuing.

### Phase 4 — Bash rendering

Implement:

- `BashRenderer`
- renderer tests

Review before continuing.

### Phase 5 — HTTP API

Implement:

- `POST /jobs`
- JSON response
- Bash response via content negotiation
- status/error translation

Review before continuing.

### Phase 6 — HTTP integration tests

Implement the API contract tests.

Review before continuing.

### Phase 7 — Quality review

Run:

```bash
mix format --check-formatted
mix test
```

Review:

- module boundaries
- error consistency
- deterministic behavior
- unnecessary complexity
- unused dependencies
- warnings

### Phase 8 — Repository polish

Add:

- `.tool-versions`
- GitHub Actions
- README
- final curl examples

Then perform a final review against both this design and the original challenge.

---

## 27. Final Acceptance Criteria

The solution is ready for submission when all of the following are true:

- `POST /jobs` accepts the challenge request structure.
- Tasks are returned in a valid dependency order.
- Ordering is deterministic.
- Input order is preserved when dependencies do not require reordering.
- Missing `requires` behaves as `[]`.
- Invalid request structures are rejected.
- Duplicate task names are rejected.
- Duplicate dependencies are rejected.
- Unknown dependencies are rejected.
- Cycles are rejected.
- JSON output omits `requires`.
- Bash output contains the correct shebang.
- Bash commands are preserved verbatim.
- Commands are never executed.
- Unsupported response formats return `406`.
- Domain logic is independent from HTTP.
- No unnecessary process/state abstraction is introduced.
- Unit and HTTP integration tests pass.
- `mix format --check-formatted` passes.
- README contains complete local test/run instructions.
- CI runs formatting and tests.
- The repository contains no unnecessary infrastructure.

---

## 28. Design Principle

The guiding principle for the implementation is:

> Solve exactly the problem requested, make the behavior explicit, and keep the implementation small enough that a reviewer can understand and trust it quickly.

The solution should demonstrate senior engineering judgment through correctness, clear boundaries, predictable behavior, tests, and restraint—not through unnecessary complexity.
