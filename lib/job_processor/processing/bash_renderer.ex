defmodule JobProcessor.BashRenderer do
  @moduledoc """
  Renders ordered task commands as a Bash script without modifying them.
  """

  alias JobProcessor.Task

  @shebang "#!/usr/bin/env bash"

  @spec render([Task.t()]) :: String.t()
  def render(tasks) do
    commands = Enum.map(tasks, & &1.command)

    Enum.join([@shebang | commands], "\n") <> "\n"
  end
end
