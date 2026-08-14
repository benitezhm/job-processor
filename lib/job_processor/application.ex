defmodule JobProcessor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:job_processor, :port, 4000)

    children = [
      {Bandit, plug: JobProcessorWeb.Router, scheme: :http, port: port}
    ]

    opts = [strategy: :one_for_one, name: JobProcessor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
