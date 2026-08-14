defmodule JobProcessor.TaskParser do
  @moduledoc """
  Validates external job parameters and converts them into domain tasks.
  """

  alias JobProcessor.Error
  alias JobProcessor.Task

  @spec parse(map()) :: {:ok, [Task.t()]} | {:error, Error.t()}
  def parse(%{"tasks" => task_params}) when is_list(task_params) do
    with {:ok, tasks} <- parse_tasks(task_params),
         :ok <- validate_unique_names(tasks),
         :ok <- validate_known_dependencies(tasks) do
      {:ok, tasks}
    end
  end

  def parse(%{"tasks" => _}) do
    error(:invalid_request, "Request field 'tasks' must be a list")
  end

  def parse(_) do
    error(:invalid_request, "Request must contain a 'tasks' list")
  end

  defp parse_tasks(task_params) do
    Enum.reduce_while(task_params, {:ok, []}, fn params, {:ok, tasks} ->
      case parse_task(params) do
        {:ok, task} -> {:cont, {:ok, [task | tasks]}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, tasks} -> {:ok, Enum.reverse(tasks)}
      {:error, _error} = error -> error
    end
  end

  defp parse_task(%{"name" => name, "command" => command} = params)
       when is_binary(name) and byte_size(name) > 0 and is_binary(command) and
              byte_size(command) > 0 do
    with {:ok, requires} <- validate_requires(name, Map.get(params, "requires", [])) do
      {:ok, %Task{name: name, command: command, requires: requires}}
    end
  end

  defp parse_task(_) do
    error(:invalid_task, "Each task must contain non-empty string 'name' and 'command' fields")
  end

  defp validate_requires(name, requires) when is_list(requires) do
    if Enum.all?(requires, &is_binary/1) do
      validate_unique_dependencies(name, requires)
    else
      error(:invalid_task, "Task '#{name}' dependencies must be strings")
    end
  end

  defp validate_requires(name, _requires) do
    error(:invalid_task, "Task '#{name}' field 'requires' must be a list")
  end

  defp validate_unique_names(tasks) do
    case find_duplicate(Enum.map(tasks, & &1.name)) do
      nil -> :ok
      name -> error(:duplicate_task, "Task name '#{name}' is duplicated")
    end
  end

  defp validate_unique_dependencies(name, requires) do
    case find_duplicate(requires) do
      nil ->
        {:ok, requires}

      dependency ->
        error(:duplicate_dependency, "Task '#{name}' has duplicate dependency '#{dependency}'")
    end
  end

  defp validate_known_dependencies(tasks) do
    task_names = tasks |> Enum.map(& &1.name) |> MapSet.new()

    case find_unknown_dependency(tasks, task_names) do
      nil ->
        :ok

      {name, dependency} ->
        error(:unknown_dependency, "Task '#{name}' requires unknown task '#{dependency}'")
    end
  end

  defp find_duplicate(values) do
    Enum.reduce_while(values, MapSet.new(), fn value, seen ->
      if MapSet.member?(seen, value) do
        {:halt, value}
      else
        {:cont, MapSet.put(seen, value)}
      end
    end)
    |> case do
      %MapSet{} -> nil
      duplicate -> duplicate
    end
  end

  defp find_unknown_dependency(tasks, task_names) do
    Enum.find_value(tasks, &unknown_dependency(&1, task_names))
  end

  defp unknown_dependency(task, task_names) do
    case Enum.find(task.requires, &(not MapSet.member?(task_names, &1))) do
      nil -> nil
      dependency -> {task.name, dependency}
    end
  end

  @spec error(Error.code(), String.t()) :: {:error, Error.t()}
  defp error(code, message), do: {:error, %Error{code: code, message: message}}
end
