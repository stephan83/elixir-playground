defmodule Needy.Example.Loop do
  @moduledoc """
  Loop is an example server that periodically logs a number from the Sequence server.
  """

  alias Needy.Example.{Sequence, Log}

  @name __MODULE__

  @doc """
  Returns the `child_spec` of the server.
  """
  @spec child_spec(term) :: Supervisor.child_spec
  def child_spec(_opts) do
    %{id: @name, start: {@name, :start_link, []}}
  end

  @doc """
  Starts the server.
  """
  @spec start_link() :: {:ok, pid}
  def start_link() do
    pid = spawn_link(@name, :loop, [])
    {:ok, pid}
  end

  @doc """
  Needs returns the servers that should be started before this one.
  """
  @spec needs() :: [Needy.Dependencies.spec]
  def needs(), do: [Sequence, Log]

  @spec loop() :: nil
  def loop() do
    Log.info("Loop tells Log the next number given by Sequence is #{Sequence.next()}.")
    :timer.sleep(1000)
    loop()
  end
end
