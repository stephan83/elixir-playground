defmodule Needy.Dependencies do
  @moduledoc """
  Contains types to deal with dependencies.

  This module exposes functions to sort dependencies and dependents topologically. This is useful
  to figure out in which orders things should be started or stopped.
  """

  @type child_spec :: Supervisor.child_spec()
  @type spec :: child_spec | {module, term} | module

  @typedoc """
  An error that is returned when there is a cyclic dependency.
  """
  @type cyclic_error :: {:error, :cyclic_dependency}

  @doc """
  Returns dependencies in topological order.

  The returned dependencies include the spec itself.
  """
  @spec dependencies(spec) :: {:ok, [child_spec]} | cyclic_error
  def dependencies(spec) do
    spec = Supervisor.child_spec(spec, [])

    with {:ok, deps, _} <- do_topological_sort(spec, &needs/1, %{}, nil) do
      {:ok, deps}
    end
  end

  @doc """
  Returns dependents in topological order.

  The returned dependents include the spec itself.
  """
  @spec dependents(spec, [spec]) :: {:ok, [child_spec]} | cyclic_error
  def dependents(spec, all_specs) do
    spec = Supervisor.child_spec(spec, [])
    get_children = &needed_by(&1, all_specs)

    with {:ok, deps, _} <- do_topological_sort(spec, get_children, %{}, nil) do
      {:ok, deps}
    end
  end

  @doc """
  Returns the direct dependencies of a spec.
  """
  @spec needs(spec) :: [child_spec]
  def needs(spec) do
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

  @doc """
  Returns the direct dependents of a spec given a list of specs.
  """
  @spec needed_by(spec, [spec]) :: [child_spec]
  def needed_by(spec, all_specs) do
    spec = Supervisor.child_spec(spec, [])

    all_specs
    |> Enum.map(&Supervisor.child_spec(&1, []))
    |> Enum.filter(&(spec in needs(&1)))
  end

  #===============================================================================================
  # Internals
  #===============================================================================================

  defp do_topological_sort(_spec, _get_children, marks, :visited), do: {:ok, [], marks}

  defp do_topological_sort(_spec, _get_children, _marks, :visiting),
    do: {:error, :cyclic_dependency}

  defp do_topological_sort(spec, get_children, marks, _mark) do
    with children = get_children.(spec),
         marks = Map.put(marks, spec, :visiting),
         acc = {:ok, [], marks},
         reducer = make_reducer(get_children),
         {:ok, children, marks} <- Enum.reduce_while(children, acc, reducer) do
      {:ok, children ++ [spec], Map.put(marks, spec, :visited)}
    end
  end

  defp make_reducer(get_children) do
    fn
      spec, {:ok, deps, marks} ->
        case do_topological_sort(spec, get_children, marks, marks[spec]) do
          {:ok, new_deps, new_marks} -> {:cont, {:ok, deps ++ new_deps, new_marks}}
          err -> {:halt, err}
        end

      _spec, err = {:error, _reason} ->
        err
    end
  end
end
