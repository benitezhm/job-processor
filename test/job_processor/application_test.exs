defmodule JobProcessor.ApplicationTest do
  use ExUnit.Case, async: false

  test "supervises Bandit" do
    assert [{_id, pid, :supervisor, [Bandit]}] =
             Supervisor.which_children(JobProcessor.Supervisor)

    assert Process.alive?(pid)
  end
end
