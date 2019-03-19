defmodule Services.Dependencies do
  @moduledoc """
  Contains types to deal with service dependencies.
  """

  @doc """
  Returns the dependencies of a service in topological order.

  Services can be started in the returned order to respect dependencies.

  The returned dependencies include the service itself.

  It raises a `RuntimeError` if there are cyclic dependencies.
  """
  @spec topological_sort(module()) :: [module()]
  def topological_sort(service) do
    elem(do_topological_sort(service, %{}, nil), 0)
  end

  @typep mark :: :visited | :visiting | nil
  @typep mark_map :: %{required(module()) => mark()}

  @spec do_topological_sort(module(), mark_map(), mark()) :: {[module()], mark_map()}
  defp do_topological_sort(_service, marks, :visited), do: {[], marks}
  defp do_topological_sort(_service, _marks, :visiting), do: raise(RuntimeError)

  defp do_topological_sort(service, marks, _mark) do
    direct_deps = apply(service, :needs, [])
    marks = Map.put(marks, service, :visiting)
    {indirect_deps, marks} = Enum.reduce(direct_deps, {[], marks}, &reduce/2)

    {indirect_deps ++ [service], Map.put(marks, service, :visited)}
  end

  @spec reduce(module(), {[module()], mark_map()}) :: {[module()], mark_map()}
  defp reduce(service, {deps, marks}) do
    {new_deps, new_marks} = do_topological_sort(service, marks, marks[service])
    {deps ++ new_deps, new_marks}
  end
end
