defmodule JobProcessor.DomainStructsTest do
  use ExUnit.Case, async: true

  alias JobProcessor.Error
  alias JobProcessor.Task

  test "task has the documented fields and defaults requires to an empty list" do
    task = %Task{name: "task-1", command: "echo hello"}

    assert task.name == "task-1"
    assert task.command == "echo hello"
    assert task.requires == []
  end

  test "error contains a code and message" do
    error = %Error{code: :invalid_task, message: "Task is invalid"}

    assert error.code == :invalid_task
    assert error.message == "Task is invalid"
  end
end
