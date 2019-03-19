defmodule Services.Example.Sequence do
  @moduledoc """
  Sequence is an example service that increments a number when calling `next/0`.
  """

  use Services.Service
  use Agent

  @name __MODULE__

  @doc """
  Starts the service.
  """
  @impl true
  def start_link(), do: Agent.start_link(fn -> 0 end, name: @name)

  @doc """
  Returns the next number in the sequence.
  """
  @spec next() :: integer()
  def next, do: Agent.get_and_update(@name, &{&1, &1 + 1})
end
