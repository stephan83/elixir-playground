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

  @normal_modules [
    ModuleA,
    ModuleB,
    ModuleC,
    ModuleD,
    ModuleE,
    ModuleF
  ]

  defmodule ModuleA do
    use Agent
    def needs, do: [ModuleB, ModuleC]
  end

  defmodule ModuleB do
    use Agent
    def needs, do: []
  end

  defmodule ModuleC do
    use Agent
    def needs, do: [ModuleB, ModuleD]
  end

  defmodule ModuleD do
    use Agent
    def needs, do: [ModuleE]
  end

  defmodule ModuleE do
    use Agent
  end

  defmodule ModuleF do
    use Agent
    def needs, do: [ModuleG]
  end

  defmodule ModuleG do
    use Agent
    def needs, do: [ModuleF, ModuleE]
  end

  defmodule ModuleH do
    use Agent
    def needs(opts), do: Keyword.get(opts, :needs, [])
  end

  describe "dependencies/1" do
    test "sorts dependencies in correct order" do
      expected =
        [ModuleB, ModuleE, ModuleD, ModuleC, ModuleA]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.dependencies(ModuleA) == {:ok, expected}
    end

    test "handles dynamic dependencies" do
      spec = {ModuleH, needs: [ModuleE]}

      expected =
        [ModuleE, spec]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.dependencies(spec) == {:ok, expected}
    end

    test "handles nested dynamic dependencies" do
      spec_b = {ModuleH, needs: [ModuleE]}
      spec_a = {ModuleH, needs: [spec_b]}

      expected =
        [ModuleE, spec_b, spec_a]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.dependencies(spec_a) == {:ok, expected}
    end

    test "returns an error if there is a cyclic dependency" do
      assert Dependencies.dependencies(ModuleF) == {:error, :cyclic_dependency}
    end
  end

  describe "dependents/1" do
    test "sorts dependents in correct order" do
      expected =
        [ModuleA, ModuleC, ModuleD, ModuleE]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.dependents(ModuleE, @normal_modules) == {:ok, expected}
    end
  end

  describe "needs/1" do
    test "returns the direct dependencies of a spec" do
      expected =
        [ModuleB, ModuleC]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.needs(ModuleA) == expected
    end

    test "returns an empty list if a spec doesn't specify dependencies" do
      assert Dependencies.needs(ModuleE) == []
    end
  end

  describe "needed_by/1" do
    test "returns the direct dependents of a spec" do
      expected =
        [ModuleD]
        |> Enum.map(&Supervisor.child_spec(&1, []))

      assert Dependencies.needed_by(ModuleE, @normal_modules) == expected
    end
  end
end
