defmodule JobProcessor.TaskSorterTest do
  use ExUnit.Case, async: true

  alias JobProcessor.Error
  alias JobProcessor.Task
  alias JobProcessor.TaskSorter

  describe "sort/1 with acyclic tasks" do
    test "sorts the challenge example" do
      tasks = [
        task("task-1"),
        task("task-2", ["task-3"]),
        task("task-3", ["task-1"]),
        task("task-4", ["task-2", "task-3"])
      ]

      assert {:ok, ordered_tasks} = TaskSorter.sort(tasks)
      assert names(ordered_tasks) == ["task-1", "task-3", "task-2", "task-4"]
    end

    test "sorts one task" do
      task = task("only-task")

      assert {:ok, [^task]} = TaskSorter.sort([task])
    end

    test "sorts an empty list" do
      assert {:ok, []} = TaskSorter.sort([])
    end

    test "sorts a linear chain" do
      tasks = [task("C", ["B"]), task("B", ["A"]), task("A")]

      assert {:ok, ordered_tasks} = TaskSorter.sort(tasks)
      assert names(ordered_tasks) == ["A", "B", "C"]
    end

    test "preserves request order for independent tasks" do
      tasks = [task("C"), task("A"), task("B")]

      assert {:ok, ordered_tasks} = TaskSorter.sort(tasks)
      assert names(ordered_tasks) == ["C", "A", "B"]
    end

    test "orders tasks correctly when one task unlocks multiple dependants" do
      tasks = [task("A"), task("B", ["A"]), task("C", ["A"])]

      assert {:ok, ordered_tasks} = TaskSorter.sort(tasks)
      assert names(ordered_tasks) == ["A", "B", "C"]
    end

    test "orders a task after all of its dependencies are resolved" do
      tasks = [
        task("D", ["B", "C"]),
        task("B", ["A"]),
        task("C", ["A"]),
        task("A")
      ]

      assert {:ok, ordered_tasks} = TaskSorter.sort(tasks)
      assert_before(ordered_tasks, "A", "B")
      assert_before(ordered_tasks, "A", "C")
      assert_before(ordered_tasks, "B", "D")
      assert_before(ordered_tasks, "C", "D")
    end

    test "uses original request order to choose between currently ready tasks" do
      tasks = [task("A", ["B"]), task("B"), task("C")]

      assert {:ok, ordered_tasks} = TaskSorter.sort(tasks)
      assert names(ordered_tasks) == ["B", "A", "C"]
    end
  end

  describe "sort/1 with cyclic tasks" do
    test "rejects a direct cycle" do
      assert_cycle([task("A", ["B"]), task("B", ["A"])])
    end

    test "rejects an indirect cycle" do
      assert_cycle([task("A", ["C"]), task("B", ["A"]), task("C", ["B"])])
    end

    test "rejects a self-cycle" do
      assert_cycle([task("A", ["A"])])
    end
  end

  defp task(name, requires \\ []) do
    %Task{name: name, command: "echo #{name}", requires: requires}
  end

  defp names(tasks), do: Enum.map(tasks, & &1.name)

  defp assert_before(tasks, first, second) do
    ordered_names = names(tasks)

    assert Enum.find_index(ordered_names, &(&1 == first)) <
             Enum.find_index(ordered_names, &(&1 == second))
  end

  defp assert_cycle(tasks) do
    assert {:error,
            %Error{
              code: :cyclic_dependency,
              message: "Task dependencies contain a cycle"
            }} = TaskSorter.sort(tasks)
  end
end
