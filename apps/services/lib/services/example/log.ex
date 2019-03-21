defmodule Services.Example.Log do
  @moduledoc """
  Log is an example service using GenServer.
  """

  use GenServer

  require Logger

  @name __MODULE__

  @doc """
  Starts the service.
  """
  def start_link(_opts), do: GenServer.start(@name, nil, name: @name)

  @doc false
  @impl true
  @spec init(any()) :: {:ok, nil}
  def init(_), do: {:ok, nil}

  @doc """
  Outputs an info log message.
  """
  def info(msg), do: GenServer.cast(@name, {:info, msg})

  @impl true
  def handle_cast({:info, msg}, _) do
    Logger.info(msg)
    {:noreply, nil}
  end
end
