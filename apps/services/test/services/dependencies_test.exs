defmodule Services.DependenciesTest do
  use ExUnit.Case

  alias Services.Dependencies

  alias Services.DependenciesTest.{
    ModuleA,
    ModuleB,
    ModuleC,
    ModuleD,
    ModuleE,
    ModuleF,
    ModuleG
  }

  defmodule ModuleA do
    def needs, do: [ModuleB, ModuleC]
  end

  defmodule ModuleB do
    def needs, do: []
  end

  defmodule ModuleC do
    def needs, do: [ModuleB, ModuleD]
  end

  defmodule ModuleD do
    def needs, do: [ModuleE]
  end

  defmodule ModuleE do
    def needs, do: []
  end

  defmodule ModuleF do
    def needs, do: [ModuleG]
  end

  defmodule ModuleG do
    def needs, do: [ModuleF]
  end

  describe "topological_sort" do
    test "sorts dependencies correctly" do
      assert Dependencies.topological_sort(ModuleA) == [
               ModuleB,
               ModuleE,
               ModuleD,
               ModuleC,
               ModuleA
             ]
    end

    test "returns an error if there is a cyclic dependency" do
      assert Dependencies.topological_sort(ModuleF) == {:error, :cyclic_dependency}
    end
  end
end
