defmodule Services.Application do
  @moduledoc false

  use Application

  @impl true
  @spec start(term(), term()) :: {:ok, pid()}
  def start(_type, _args), do: Services.Supervisor.start_link()
end
