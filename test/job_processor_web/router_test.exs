defmodule JobProcessorWeb.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias JobProcessorWeb.Router

  test "returns 404 for an unhandled request" do
    conn = conn(:get, "/") |> Router.call(Router.init([]))

    assert conn.status == 404
    assert conn.resp_body == "Not Found"
  end
end
