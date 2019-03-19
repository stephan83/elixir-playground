defmodule Services.Example.Log do
  @moduledoc """
  Log is an example service using GenServer.
  """

  use Services.Service
  use GenServer

  require Logger

  @name __MODULE__

  @doc """
  Starts the service.
  """
  @impl true
  def start_link() do
    GenServer.start(@name, nil, name: @name)
  end

  @impl true
  def init(_) do
    {:ok, nil}
  end

  @doc """
  Outputs an info log message.
  """
  def info(msg) do
    GenServer.cast(@name, {:info, msg})
  end

  @impl true
  def handle_cast({:info, msg}, _) do
    Logger.info(msg)
    {:noreply, nil}
  end
end
