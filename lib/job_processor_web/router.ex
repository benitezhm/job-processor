defmodule JobProcessorWeb.Router do
  @moduledoc false

  use Plug.Router

  alias JobProcessor.BashRenderer
  alias JobProcessor.Error
  alias JobProcessor.TaskParser
  alias JobProcessor.TaskSorter

  @json_parser_options Plug.Parsers.init(
                         parsers: [:json],
                         pass: ["*/*"],
                         json_decoder: Jason
                       )

  plug(:parse_json)
  plug(:match)
  plug(:dispatch)

  post "/jobs" do
    with {:ok, representation} <- negotiate_response(conn),
         {:ok, tasks} <- TaskParser.parse(conn.body_params),
         {:ok, ordered_tasks} <- TaskSorter.sort(tasks) do
      send_success(conn, representation, ordered_tasks)
    else
      {:error, :not_acceptable} -> send_resp(conn, 406, "Not Acceptable")
      {:error, %Error{} = error} -> send_domain_error(conn, error)
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

  defp parse_json(conn, _opts) do
    Plug.Parsers.call(conn, @json_parser_options)
  rescue
    _error in [Plug.Parsers.ParseError, Plug.Parsers.BadEncodingError] ->
      conn
      |> send_domain_error(%Error{
        code: :invalid_request,
        message: "Request body is not valid JSON"
      })
      |> halt()
  end

  defp negotiate_response(conn) do
    case get_req_header(conn, "accept") do
      [] -> {:ok, :json}
      values -> find_representation(values)
    end
  end

  # Full RFC-style quality weighting was considered but intentionally left out to keep the service proportionate to the assignment.
  # For this small challenge, client order intentionally replaces full q-value prioritization.
  defp find_representation(values) do
    values
    |> Enum.flat_map(&Plug.Conn.Utils.list/1)
    |> Enum.find_value(fn media_range ->
      case Plug.Conn.Utils.media_type(media_range) do
        {:ok, type, subtype, _params} -> representation(type, subtype)
        :error -> nil
      end
    end)
    |> case do
      nil -> {:error, :not_acceptable}
      representation -> {:ok, representation}
    end
  end

  defp representation("*", "*"), do: :json
  defp representation("application", subtype) when subtype in ["json", "*"], do: :json
  defp representation("text", subtype) when subtype in ["plain", "*"], do: :bash
  defp representation(_type, _subtype), do: nil

  defp send_success(conn, :json, tasks) do
    payload = %{
      "tasks" => Enum.map(tasks, &%{"name" => &1.name, "command" => &1.command})
    }

    send_json(conn, 200, payload)
  end

  defp send_success(conn, :bash, tasks) do
    conn
    |> put_resp_content_type("text/plain", "utf-8")
    |> send_resp(200, BashRenderer.render(tasks))
  end

  defp send_domain_error(conn, %Error{} = error) do
    status = if error.code == :cyclic_dependency, do: 422, else: 400

    send_json(conn, status, %{
      "error" => %{
        "code" => Atom.to_string(error.code),
        "message" => error.message
      }
    })
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
