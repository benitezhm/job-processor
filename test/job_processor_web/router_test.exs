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

  test "uses the first supported media type" do
    bash_conn = post_jobs("text/plain, application/json")
    json_conn = post_jobs("application/json, text/plain")

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
      conn = post_jobs(accept)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == [content_type]
    end
  end

  test "returns 406 when no media type is supported" do
    conn = post_jobs("application/xml, image/png")

    assert conn.status == 406
    assert conn.resp_body == "Not Acceptable"
  end

  defp post_jobs(accept) do
    :post
    |> conn("/jobs", Jason.encode!(%{"tasks" => []}))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", accept)
    |> Router.call(Router.init([]))
  end
end
