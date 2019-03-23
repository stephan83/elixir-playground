defmodule Needy.Example.Sequence do
  @moduledoc """
  Sequence is an example server that increments a number when calling `next/0`.
  """

  use Agent

  @name __MODULE__

  @doc """
  Starts the server.
  """
  @spec start_link(term) :: Agent.on_start()
  def start_link(_opts), do: Agent.start_link(fn -> 0 end, name: @name)

  @doc """
  Returns the next number in the sequence.
  """
  @spec next() :: integer()
  def next, do: Agent.get_and_update(@name, &{&1, &1 + 1})
end
