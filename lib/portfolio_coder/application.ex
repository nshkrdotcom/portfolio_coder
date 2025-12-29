defmodule PortfolioCoder.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Register code-specific tools with the agent framework
      {Task, fn -> PortfolioCoder.Tools.register_all() end}
    ]

    opts = [strategy: :one_for_one, name: PortfolioCoder.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
