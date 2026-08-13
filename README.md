# JobProcessor

**TODO: Add description**

## Requirements

Tested with Erlang/OTP 28.0.1 and Elixir 1.18.4 compiled for OTP 28. The exact asdf
versions are pinned in `.tool-versions`.

## Quality

```sh
mix format --check-formatted
mix test
mix credo --strict
mix dialyzer
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `job_processor` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:job_processor, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/job_processor>.
