defmodule Services.Service do
  @moduledoc """
  Service defines the behaviour of a service.

  It must at least implement the `start_link` function.
  """

  @doc """
  Called to start the service.
  """
  @callback start_link() :: {:ok, pid()} | {:error, term()}

  @doc """
  Called to check if any services should be running before starting the service.
  """
  @callback needs :: [atom]

  defmacro __using__(_) do
    quote do
      @behaviour Services.Service
      def needs(), do: []
      defoverridable(needs: 0)
    end
  end
end
