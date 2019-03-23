defmodule Needy.Dependencies do
  @moduledoc """
  Contains types to deal with dependencies.
  """

  @type child_spec :: Supervisor.child_spec()
  @type spec :: child_spec | {module, term} | module

  @typedoc """
  An error that is returned when there is a cyclic dependency.
  """
  @type cyclic_error :: {:error, :cyclic_dependency}

  @doc """
  Returns dependencies in topological order.

  Child specs can be started in the returned order to respect dependencies.

  The returned dependencies include the spec itself.
  """
  @spec topological_sort(spec) :: {:ok, [child_spec]} | cyclic_error
  def topological_sort(spec) do
    spec = Supervisor.child_spec(spec, [])

    with {:ok, deps, _} <- do_topological_sort(spec, %{}, nil) do
      {:ok, deps}
    end
  end

  @doc """
  Returns the direct dependencies of a spec.
  """
  @spec get_deps(spec) :: [child_spec]
  def get_deps(spec) do
    {module, _, args} = Supervisor.child_spec(spec, []).start

    deps =
      cond do
        function_exported?(module, :needs, length(args)) ->
          apply(module, :needs, args)

        function_exported?(module, :needs, 0) ->
          apply(module, :needs, [])

        true ->
          []
      end

    Enum.map(deps, &Supervisor.child_spec(&1, []))
  end

  defp do_topological_sort(_spec, marks, :visited), do: {:ok, [], marks}
  defp do_topological_sort(_spec, _marks, :visiting), do: {:error, :cyclic_dependency}

  defp do_topological_sort(spec, marks, _mark) do
    with deps = get_deps(spec),
         marks = Map.put(marks, spec, :visiting),
         {:ok, deps, marks} <- Enum.reduce_while(deps, {:ok, [], marks}, &reduce/2) do
      {:ok, deps ++ [spec], Map.put(marks, spec, :visited)}
    end
  end

  defp reduce(_spec, err = {:error, _reason}), do: err

  defp reduce(spec, {:ok, deps, marks}) do
    case do_topological_sort(spec, marks, marks[spec]) do
      {:ok, new_deps, new_marks} -> {:cont, {:ok, deps ++ new_deps, new_marks}}
      err -> {:halt, err}
    end
  end
end
