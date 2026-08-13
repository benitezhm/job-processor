defmodule JobProcessorWeb.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias JobProcessorWeb.Router

  test "returns 404 for an unhandled request" do
    conn = conn(:get, "/") |> Router.call(Router.init([]))

    assert conn.status == 404
    assert conn.resp_body == "Not Found"
  end

  test "returns ordered tasks as JSON without dependency fields" do
    conn = post_jobs(job(), "application/json")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

    assert Jason.decode!(conn.resp_body) == %{
             "tasks" => [
               %{"name" => "task-1", "command" => "touch /tmp/file1"},
               %{"name" => "task-2", "command" => "cat /tmp/file1"}
             ]
           }
  end

  test "returns ordered commands as Bash" do
    conn = post_jobs(job(), "text/plain")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]

    assert conn.resp_body ==
             "#!/usr/bin/env bash\ntouch /tmp/file1\ncat /tmp/file1\n"
  end

  test "defaults to JSON when Accept is absent" do
    conn = post_jobs(%{"tasks" => []})

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    assert Jason.decode!(conn.resp_body) == %{"tasks" => []}
  end

  test "returns JSON errors for malformed and invalid requests" do
    malformed_conn = post_json("{")
    invalid_conn = post_jobs(%{})

    for conn <- [malformed_conn, invalid_conn] do
      assert conn.status == 400
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      assert %{"error" => %{"code" => "invalid_request", "message" => message}} =
               Jason.decode!(conn.resp_body)

      assert is_binary(message)
    end
  end

  test "returns 422 for cyclic dependencies" do
    params = %{
      "tasks" => [
        %{"name" => "task-1", "command" => "echo task-1", "requires" => ["task-1"]}
      ]
    }

    conn = post_jobs(params)

    assert conn.status == 422

    assert Jason.decode!(conn.resp_body) == %{
             "error" => %{
               "code" => "cyclic_dependency",
               "message" => "Task dependencies contain a cycle"
             }
           }
  end

  test "uses the first supported media type" do
    bash_conn = post_jobs(%{"tasks" => []}, "text/plain, application/json")
    json_conn = post_jobs(%{"tasks" => []}, "application/json, text/plain")

    assert get_resp_header(bash_conn, "content-type") == ["text/plain; charset=utf-8"]
    assert get_resp_header(json_conn, "content-type") == ["application/json; charset=utf-8"]
  end

  test "skips unsupported media types and supports wildcards" do
    expectations = [
      {"application/xml, application/*", "application/json; charset=utf-8"},
      {"text/*", "text/plain; charset=utf-8"},
      {"*/*", "application/json; charset=utf-8"}
    ]

    for {accept, content_type} <- expectations do
      conn = post_jobs(%{"tasks" => []}, accept)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == [content_type]
    end
  end

  test "returns 406 when no media type is supported" do
    conn = post_jobs(%{"tasks" => []}, "application/xml, image/png")

    assert conn.status == 406
    assert conn.resp_body == "Not Acceptable"
  end

  defp post_jobs(params, accept \\ nil) do
    params
    |> Jason.encode!()
    |> post_json(accept)
  end

  defp post_json(body, accept \\ nil) do
    :post
    |> conn("/jobs", body)
    |> put_req_header("content-type", "application/json")
    |> put_accept(accept)
    |> Router.call(Router.init([]))
  end

  defp put_accept(conn, nil), do: conn
  defp put_accept(conn, accept), do: put_req_header(conn, "accept", accept)

  defp job do
    %{
      "tasks" => [
        %{
          "name" => "task-2",
          "command" => "cat /tmp/file1",
          "requires" => ["task-1"]
        },
        %{"name" => "task-1", "command" => "touch /tmp/file1"}
      ]
    }
  end
end
