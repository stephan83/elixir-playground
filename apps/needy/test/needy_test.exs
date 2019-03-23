defmodule NeeyTest do
  use ExUnit.Case

  alias Needy.Example.{Log, Loop, Sequence}

  setup do
    sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
    start_supervised!({Needy, supervisor: sup})
    :ok
  end

  describe "start/2" do
    test "starts all dependencies" do
      assert {:ok, pid} = Needy.start(Loop)
      assert is_pid(pid)
      assert Needy.status(Log) == :running
      assert Needy.status(Loop) == :running
      assert Needy.status(Sequence) == :running
    end
  end

  describe "stop/2" do
    test "stops if possible" do
      Needy.start(Loop)
      assert :ok = Needy.stop(Loop)
      assert Needy.status(Log) == :running
      assert Needy.status(Loop) == :stopped
      assert Needy.status(Sequence) == :running
    end

    test "returns an error if needed by others" do
      Needy.start(Loop)
      assert {:error, :needed} == Needy.stop(Log)
      assert Needy.status(Log) != :stopped
    end
  end

  describe "can_stop?/2" do
    test "returns false when stopped" do
      refute Needy.can_stop?(Log)
      refute Needy.can_stop?(Loop)
      refute Needy.can_stop?(Sequence)
    end

    test "returns true when running but not needed" do
      Needy.start(Loop)
      assert Needy.can_stop?(Loop)
    end

    test "returns false when running but needed" do
      Needy.start(Loop)
      refute Needy.can_stop?(Log)
      refute Needy.can_stop?(Sequence)
    end
  end

  describe "lookup/2" do
    test "returns nil if stopped" do
      assert Needy.lookup(Log) == nil
      assert Needy.lookup(Loop) == nil
      assert Needy.lookup(Sequence) == nil
    end

    test "returns a pid if running" do
      Needy.start(Loop)
      assert is_pid(Needy.lookup(Log))
      assert is_pid(Needy.lookup(Loop))
      assert is_pid(Needy.lookup(Sequence))
    end

    test "returns nil after started then stopped" do
      Needy.start(Log)
      assert is_pid(Needy.lookup(Log))
      Needy.stop(Log)
      assert Needy.lookup(Log) == nil
    end
  end
end

