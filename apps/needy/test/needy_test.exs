defmodule NeedyTest do
  use ExUnit.Case

  alias Needy.Example.{Log, Loop, Sequence}

  describe "start/2" do
    setup :default

    test "starts all dependencies" do
      assert {:ok, pid} = Needy.start(Loop)
      assert is_pid(pid)
      assert Needy.status(Log) == :running
      assert Needy.status(Loop) == :running
      assert Needy.status(Sequence) == :running
    end

    test "does nothing if already running" do
      Needy.start(Log)
      assert Needy.start(Log) == nil
    end
  end

  describe "stop/2" do
    setup :default

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
    setup :default

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
    setup :default

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

  describe "start_link/1" do
    test "returns an error without a supervisor" do
      assert {:error, :no_supervisor} = Needy.start_link([])
    end

    test "server does not stop if a dependency crashes and :stop_dependent is false" do
      start_link(stop_dependents: false)

      {:ok, pid} = Needy.start(Log)
      Needy.start(Loop)
      Process.exit(pid, :crash)
      assert Needy.status(Log) == :stopped
      assert Needy.status(Loop) == :running
      assert Needy.status(Sequence) == :running
    end

    test "server stops if a dependency crashes :stop_dependents is true" do
      start_link(stop_dependents: true)

      {:ok, pid} = Needy.start(Log)
      Needy.start(Loop)
      Process.exit(pid, :crash)
      assert Needy.status(Log) == :stopped
      assert Needy.status(Loop) == :stopped
      assert Needy.status(Sequence) == :running
    end

    test "servers restarts if a dependency crashes :restart_dependents is true" do
      start_link(stop_dependents: true, restart_dependents: true)

      {:ok, pid} = Needy.start(Log)
      Needy.start(Loop)
      Process.exit(pid, :crash)
      # TODO: find a way to remove sleep()
      Process.sleep(100)
      assert Needy.status(Log) == :running
      assert Needy.status(Loop) == :running
      assert Needy.status(Sequence) == :running
    end

    test "servers does not restart if a dependency crashes and :restart_dependents is false" do
      start_link(stop_dependents: true, restart_dependents: false)

      {:ok, pid} = Needy.start(Log)
      Needy.start(Loop)
      Process.exit(pid, :crash)
      # TODO: find a way to remove sleep()
      Process.sleep(100)
      assert Needy.status(Log) == :stopped
      assert Needy.status(Loop) == :stopped
      assert Needy.status(Sequence) == :running
    end

    test "servers does not restart if a dependency stops normally and :restart_dependents is true" do
      start_link(stop_dependents: true, restart_dependents: true)

      {:ok, pid} = Needy.start(Sequence)
      Needy.start(Loop)
      Process.exit(pid, :shutdown)
      # TODO: find a way to remove sleep()
      Process.sleep(100)
      assert Needy.status(Log) == :running
      assert Needy.status(Loop) == :stopped
      assert Needy.status(Sequence) == :stopped
    end
  end

  defp default(_context), do: start_link()

  defp start_link(opts \\ []) do
    opts =
      if Keyword.has_key?(opts, :supervisor) do
        opts
      else
        sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
        Keyword.put(opts, :supervisor, sup)
      end

    start_supervised!({Needy, opts})
    :ok
  end
end
