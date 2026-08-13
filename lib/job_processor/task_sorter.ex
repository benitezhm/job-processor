defmodule JobProcessor.TaskSorter do
  @moduledoc """
  Orders validated tasks while preserving their dependency constraints.
  """

  alias JobProcessor.Error
  alias JobProcessor.Task

  @spec sort([Task.t()]) :: {:ok, [Task.t()]} | {:error, Error.t()}
  def sort(tasks) do
    indexed_tasks = Enum.with_index(tasks)

    graph = %{
      task_by_name: Map.new(tasks, &{&1.name, &1}),
      original_index: Map.new(indexed_tasks, fn {task, index} -> {task.name, index} end),
      dependants: build_dependants(tasks),
      task_count: length(tasks)
    }

    state = %{
      ready: build_ready_set(indexed_tasks),
      dependency_count: Map.new(tasks, &{&1.name, length(&1.requires)}),
      result: [],
      processed_count: 0
    }

    traverse(graph, state)
  end

  defp build_dependants(tasks) do
    Enum.reduce(tasks, %{}, fn task, dependants ->
      Enum.reduce(task.requires, dependants, fn dependency, dependants ->
        Map.update(dependants, dependency, [task.name], &[task.name | &1])
      end)
    end)
  end

  defp build_ready_set(indexed_tasks) do
    # :gb_sets keeps ready tasks ordered; {index, name} uses request order as the
    # primary tie-breaker while the validated unique name distinguishes entries.
    Enum.reduce(indexed_tasks, :gb_sets.empty(), fn
      {%Task{requires: []} = task, index}, ready -> :gb_sets.add({index, task.name}, ready)
      {_task, _index}, ready -> ready
    end)
  end

  defp traverse(graph, %{ready: ready} = state) do
    if :gb_sets.is_empty(ready) do
      finish(state.result, state.processed_count, graph.task_count)
    else
      {{_index, name}, ready} = :gb_sets.take_smallest(ready)

      # Bang operations expose broken parser/state invariants instead of masking them.
      task = Map.fetch!(graph.task_by_name, name)

      state =
        state
        |> Map.put(:ready, ready)
        |> release_dependants(Map.get(graph.dependants, name, []), graph.original_index)
        |> Map.update!(:result, &[task | &1])
        |> Map.update!(:processed_count, &(&1 + 1))

      traverse(graph, state)
    end
  end

  defp release_dependants(state, dependants, original_index) do
    Enum.reduce(dependants, state, fn name, state ->
      dependency_count = Map.update!(state.dependency_count, name, &(&1 - 1))

      if dependency_count[name] == 0 do
        %{
          state
          | ready: :gb_sets.add({Map.fetch!(original_index, name), name}, state.ready),
            dependency_count: dependency_count
        }
      else
        %{state | dependency_count: dependency_count}
      end
    end)
  end

  defp finish(result, task_count, task_count), do: {:ok, Enum.reverse(result)}

  defp finish(_result, _processed_count, _task_count) do
    # With Kahn's algorithm, if the ready set becomes empty before all nodes are processed, the graph contains a cycle.
    {:error,
     %Error{
       code: :cyclic_dependency,
       message: "Task dependencies contain a cycle"
     }}
  end
end
