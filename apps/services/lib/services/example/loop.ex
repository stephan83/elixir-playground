defmodule Services.Example.Loop do
  @moduledoc """
  Loop is an example service that periodically prints a number from the Sequence service.
  """

  use Services.Service

  alias Services.Example.Sequence

  require Logger

  @name __MODULE__

  @doc """
  Needs returns the services that should be started before this one.
  """
  @impl true
  def needs, do: [Sequence]

  @doc """
  Starts the service.
  """
  @impl true
  def start_link() do
    pid = spawn_link(@name, :loop, [])
    {:ok, pid}
  end

  @spec loop() :: nil
  def loop() do
    Logger.info("Looper says the next number of Sequence is #{Sequence.next()}.")
    :timer.sleep(1000)
    loop()
  end
end
