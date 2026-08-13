defmodule JobProcessor.TaskParserTest do
  use ExUnit.Case, async: true

  alias JobProcessor.Error
  alias JobProcessor.Task
  alias JobProcessor.TaskParser

  describe "parse/1 with valid input" do
    test "converts a task without requires and applies the default" do
      params = %{"tasks" => [%{"name" => "task-1", "command" => "echo hello"}]}

      assert {:ok, [%Task{name: "task-1", command: "echo hello", requires: []}]} =
               TaskParser.parse(params)
    end

    test "converts tasks with dependencies" do
      params = %{
        "tasks" => [
          %{"name" => "task-1", "command" => "touch /tmp/file1"},
          %{
            "name" => "task-2",
            "command" => "cat /tmp/file1",
            "requires" => ["task-1"]
          }
        ]
      }

      assert {:ok,
              [
                %Task{name: "task-1", command: "touch /tmp/file1", requires: []},
                %Task{name: "task-2", command: "cat /tmp/file1", requires: ["task-1"]}
              ]} = TaskParser.parse(params)
    end

    test "accepts an empty task list" do
      assert {:ok, []} = TaskParser.parse(%{"tasks" => []})
    end
  end

  describe "parse/1 request validation" do
    test "rejects a request without tasks" do
      assert {:error, %Error{code: :invalid_request}} = TaskParser.parse(%{})
    end

    test "rejects a non-list tasks value" do
      assert {:error, %Error{code: :invalid_request}} =
               TaskParser.parse(%{"tasks" => %{}})
    end
  end

  describe "parse/1 task validation" do
    test "rejects a non-map task" do
      assert {:error, %Error{code: :invalid_task}} = TaskParser.parse(%{"tasks" => ["task-1"]})
    end

    test "rejects a task without a name" do
      params = %{"tasks" => [%{"command" => "echo hello"}]}

      assert {:error, %Error{code: :invalid_task}} = TaskParser.parse(params)
    end

    test "rejects a task without a command" do
      params = %{"tasks" => [%{"name" => "task-1"}]}

      assert {:error, %Error{code: :invalid_task}} = TaskParser.parse(params)
    end

    test "rejects an empty name" do
      params = %{"tasks" => [%{"name" => "", "command" => "echo hello"}]}

      assert {:error, %Error{code: :invalid_task}} = TaskParser.parse(params)
    end

    test "rejects an empty command" do
      params = %{"tasks" => [%{"name" => "task-1", "command" => ""}]}

      assert {:error, %Error{code: :invalid_task}} = TaskParser.parse(params)
    end

    test "rejects non-string names and commands" do
      assert {:error, %Error{code: :invalid_task}} =
               TaskParser.parse(%{"tasks" => [%{"name" => 1, "command" => "echo hello"}]})

      assert {:error, %Error{code: :invalid_task}} =
               TaskParser.parse(%{"tasks" => [%{"name" => "task-1", "command" => 1}]})
    end

    test "rejects a non-list requires value" do
      params = %{
        "tasks" => [%{"name" => "task-1", "command" => "echo hello", "requires" => "task-2"}]
      }

      assert {:error, %Error{code: :invalid_task}} = TaskParser.parse(params)
    end

    test "rejects a non-string dependency" do
      params = %{
        "tasks" => [%{"name" => "task-1", "command" => "echo hello", "requires" => [1]}]
      }

      assert {:error, %Error{code: :invalid_task}} = TaskParser.parse(params)
    end
  end

  describe "parse/1 relationship validation" do
    test "rejects duplicate task names" do
      params = %{
        "tasks" => [
          %{"name" => "task-1", "command" => "echo first"},
          %{"name" => "task-1", "command" => "echo second"}
        ]
      }

      assert {:error, %Error{code: :duplicate_task}} = TaskParser.parse(params)
    end

    test "rejects duplicate dependencies" do
      params = %{
        "tasks" => [
          %{"name" => "task-1", "command" => "echo first"},
          %{
            "name" => "task-2",
            "command" => "echo second",
            "requires" => ["task-1", "task-1"]
          }
        ]
      }

      assert {:error, %Error{code: :duplicate_dependency}} = TaskParser.parse(params)
    end

    test "rejects unknown dependencies" do
      params = %{
        "tasks" => [
          %{
            "name" => "task-2",
            "command" => "echo second",
            "requires" => ["task-99"]
          }
        ]
      }

      assert {:error,
              %Error{
                code: :unknown_dependency,
                message: "Task 'task-2' requires unknown task 'task-99'"
              }} = TaskParser.parse(params)
    end
  end
end
