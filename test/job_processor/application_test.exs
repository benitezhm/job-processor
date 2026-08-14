defmodule JobProcessor.ApplicationTest do
  use ExUnit.Case, async: false

  test "supervises Bandit using the test port configuration" do
    assert Application.fetch_env!(:job_processor, :port) == 0

    assert [{_id, pid, :supervisor, [Bandit]}] =
             Supervisor.which_children(JobProcessor.Supervisor)

    assert Process.alive?(pid)
  end
end
