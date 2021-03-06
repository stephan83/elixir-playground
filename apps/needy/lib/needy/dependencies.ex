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

    with {:ok, deps, _} <- sort(spec, &needs/1, [], %{}, nil) do
      {:ok, Enum.reverse(deps)}
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

    with {:ok, deps, _} <- sort(spec, get_children, [], %{}, nil) do
      {:ok, Enum.reverse(deps)}
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

  # ==============================================================================================
  # Internals
  # ==============================================================================================

  @typep get_children :: (child_spec -> [child_spec])
  @typep mark :: :visited | :visiting | nil
  @typep mark_map :: %{optional(child_spec) => mark}
  @typep reduce_ok :: {:ok, [child_spec], mark_map}
  @typep reducer :: (child_spec, reduce_ok -> {:cont, reduce_ok} | {:halt, cyclic_error})

  @spec sort(child_spec, get_children, [child_spec], mark_map, mark) :: reduce_ok | cyclic_error
  defp sort(_spec, _get_children, deps, marks, :visited) do
    {:ok, deps, marks}
  end

  defp sort(_spec, _get_children, _deps, _marks, :visiting) do
    {:error, :cyclic_dependency}
  end

  defp sort(spec, get_children, deps, marks, nil) do
    children = get_children.(spec)
    marks = Map.put(marks, spec, :visiting)
    acc = {:ok, deps, marks}
    reducer = make_reducer(get_children)

    with {:ok, deps, marks} <- Enum.reduce_while(children, acc, reducer) do
      deps = [spec | deps]
      marks = Map.put(marks, spec, :visited)
      {:ok, deps, marks}
    end
  end

  @spec make_reducer(get_children) :: reducer
  defp make_reducer(get_children) do
    fn spec, {:ok, deps, marks} ->
      case sort(spec, get_children, deps, marks, marks[spec]) do
        {:ok, deps, marks} ->
          {:cont, {:ok, deps, marks}}

        err ->
          {:halt, err}
      end
    end
  end
end
