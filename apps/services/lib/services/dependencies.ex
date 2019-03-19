defmodule Services.Dependencies do
  @moduledoc """
  Contains types to deal with service dependencies.
  """

  @typedoc """
  An error that is returned when there is a cyclic dependency.
  """
  @type cyclic_error :: {:error, :cyclic_dependency}

  @doc """
  Returns the dependencies of a service in topological order.

  Services can be started in the returned order to respect dependencies.

  The returned dependencies include the service itself.
  """
  @spec topological_sort(module()) :: [module()] | cyclic_error()
  def topological_sort(service) do
    case do_topological_sort(service, %{}, nil) do
      err = {:error, _} -> err
      {deps, _} -> deps
    end
  end

  @typep mark :: :visited | :visiting | nil
  @typep mark_map :: %{required(module()) => mark()}

  @spec do_topological_sort(module(), mark_map(), mark()) ::
          {[module()], mark_map()} | cyclic_error()
  defp do_topological_sort(_service, marks, :visited), do: {[], marks}
  defp do_topological_sort(_service, _marks, :visiting), do: {:error, :cyclic_dependency}

  defp do_topological_sort(service, marks, _mark) do
    direct_deps = apply(service, :needs, [])
    marks = Map.put(marks, service, :visiting)

    case Enum.reduce_while(direct_deps, {[], marks}, &reduce/2) do
      err = {:error, _} ->
        err

      {indirect_deps, marks} ->
        {indirect_deps ++ [service], Map.put(marks, service, :visited)}
    end
  end

  @spec reduce(module(), {[module()], mark_map()}) ::
          {:cont, {[module()], mark_map()}} | {:halt, cyclic_error()}
  defp reduce(service, {deps, marks}) do
    case do_topological_sort(service, marks, marks[service]) do
      err = {:error, _} -> {:halt, err}
      {new_deps, new_marks} -> {:cont, {deps ++ new_deps, new_marks}}
    end
  end
end
