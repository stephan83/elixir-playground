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

  defp do_topological_sort(_, marks, :visited) do
    {[], marks}
  end

  defp do_topological_sort(_, _, :visiting) do
    raise RuntimeError
  end

  defp do_topological_sort(service, marks, _) do
    direct_deps = apply(service, :needs, [])
    marks = Map.put(marks, service, :visiting)
    {indirect_deps, marks} = Enum.reduce(direct_deps, {[], marks}, &reduce/2)

    {indirect_deps ++ [service], Map.put(marks, service, :visited)}
  end

  defp reduce(service, {deps, marks}) do
    {new_deps, new_marks} = do_topological_sort(service, marks, marks[service])
    {deps ++ new_deps, new_marks}
  end
end
