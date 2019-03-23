defmodule Needy.DependenciesTest do
  use ExUnit.Case, async: true

  alias Needy.Dependencies

  alias Needy.DependenciesTest.{
    ModuleA,
    ModuleB,
    ModuleC,
    ModuleD,
    ModuleE,
    ModuleF,
    ModuleG
  }

  defmodule ModuleA do
    use Agent
    def needs(), do: [ModuleB, ModuleC]
  end

  defmodule ModuleB do
    use Agent
    def needs(), do: []
  end

  defmodule ModuleC do
    use Agent
    def needs(), do: [ModuleB, ModuleD]
  end

  defmodule ModuleD do
    use Agent
    def needs(), do: [ModuleE]
  end

  defmodule ModuleE do
    use Agent
  end

  defmodule ModuleF do
    use Agent
    def needs(), do: [ModuleG]
  end

  defmodule ModuleG do
    use Agent
    def needs(), do: [ModuleF, ModuleE]
  end

  defmodule ModuleH do
    use Agent
    def needs(opts), do: Keyword.get(opts, :needs, [])
  end

  describe "topological_sort/1" do
    test "sorts dependencies in correct order" do
      expected =
        [ModuleB, ModuleE, ModuleD, ModuleC, ModuleA]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.topological_sort(ModuleA) == {:ok, expected}
    end

    test "handles dynamic dependencies" do
      spec = {ModuleH, needs: [ModuleE]}

      expected =
        [ModuleE, spec]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.topological_sort(spec) == {:ok, expected}
    end

    test "handles nested dynamic dependencies" do
      specB = {ModuleH, needs: [ModuleE]}
      specA = {ModuleH, needs: [specB]}

      expected =
        [ModuleE, specB, specA]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.topological_sort(specA) == {:ok, expected}
    end

    test "returns an error if there is a cyclic dependency" do
      assert Dependencies.topological_sort(ModuleF) == {:error, :cyclic_dependency}
    end
  end

  describe "get_deps/1" do
    test "returns the direct dependencies of a spec" do
      expected =
        [ModuleB, ModuleC]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.get_deps(ModuleA) == expected
    end

    test "returns an empty list if a spec doesn't specify dependencies" do
      assert Dependencies.get_deps(ModuleE) == []
    end
  end
end