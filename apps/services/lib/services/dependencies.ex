defmodule Services.Dependencies do
  @moduledoc """
  Contains types to deal with service dependencies.
  """

  @typedoc """
  The spec of a service is just a `child_spec`.
  """
  @type service_spec :: Supervisor.child_spec() | {module, term} | module

  @typedoc """
  An error that is returned when there is a cyclic dependency.
  """
  @type cyclic_error :: {:error, :cyclic_dependency}

  @doc """
  Returns the dependencies of a service in topological order.

  Services can be started in the returned order to respect dependencies.

  The returned dependencies include the service itself.
  """
  @spec topological_sort(service_spec()) :: {:ok, [service_spec()]} | cyclic_error()
  def topological_sort(service) do
    service = Supervisor.child_spec(service, [])

    with {:ok, deps, _} <- do_topological_sort(service, %{}, nil) do
      {:ok, deps}
    end
  end

  @doc """
  Returns the direct dependencies of a service.
  """
  @spec get_deps(service_spec()) :: [service_spec()]
  def get_deps(service) do
    {module, _, args} = Supervisor.child_spec(service, []).start

    deps =
      cond do
        :erlang.function_exported(module, :needs, length(args)) ->
          apply(module, :needs, args)

        :erlang.function_exported(module, :needs, 0) ->
          apply(module, :needs, [])

        true ->
          []
      end

    Enum.map(deps, &Supervisor.child_spec(&1, []))
  end

  @typep mark :: :visited | :visiting | nil
  @typep mark_map :: %{required(service_spec()) => mark()}
  @typep ok :: {:ok, [service_spec()], mark_map()}
  @typep on_reduce :: {:ok, [service_spec()], mark_map()} | cyclic_error()

  @spec do_topological_sort(service_spec(), mark_map(), mark()) :: ok() | cyclic_error()
  defp do_topological_sort(_service, marks, :visited), do: {:ok, [], marks}
  defp do_topological_sort(_service, _marks, :visiting), do: {:error, :cyclic_dependency}

  defp do_topological_sort(service, marks, _mark) do
    with deps = get_deps(service),
         marks = Map.put(marks, service, :visiting),
         {:ok, deps, marks} <- Enum.reduce(deps, {:ok, [], marks}, &reduce/2) do
      {:ok, deps ++ [service], Map.put(marks, service, :visited)}
    end
  end

  @spec reduce(service_spec(), ok() | cyclic_error()) :: on_reduce()
  defp reduce(_service, err = {:error, _reason}), do: err

  defp reduce(service, {:ok, deps, marks}) do
    case do_topological_sort(service, marks, marks[service]) do
      {:ok, new_deps, new_marks} -> {:ok, deps ++ new_deps, new_marks}
      err -> err
    end
  end
end
