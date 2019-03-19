defmodule Services.Example.Loop do
  @moduledoc """
  Loop is an example service that periodically logs a number from the Sequence service.
  """

  use Services.Service

  alias Services.Example.{Sequence, Log}

  @name __MODULE__

  @doc """
  Needs returns the services that should be started before this one.
  """
  @impl true
  def needs, do: [Sequence, Log]

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
    Log.info("Loop tells Log the next number given by Sequence is #{Sequence.next()}.")
    :timer.sleep(1000)
    loop()
  end
end
