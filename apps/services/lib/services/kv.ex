defmodule Services.KV do
  @moduledoc """
  A simple key-value store.

  It is used by the service supervisor to store state related to services.
  """
  use Agent

  @name __MODULE__

  @doc """
  Starts the key-value store process.
  """
  @spec start_link(term) :: Agent.on_start()
  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: @name)

  @doc """
  Returns the value of a key.
  """
  @spec get(any()) :: any()
  def get(key), do: Agent.get(@name, &Map.get(&1, key))

  @doc """
  Puts a value in a key.
  """
  @spec put(any(), any()) :: :ok
  def put(key, value), do: Agent.update(@name, &Map.put(&1, key, value))

  @doc """
  Deletes a key
  """
  @spec delete(any()) :: :ok
  def delete(key), do: Agent.update(@name, &Map.delete(&1, key))
end
