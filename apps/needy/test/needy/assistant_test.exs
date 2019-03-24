defmodule Needy.AssistantTest do
  use ExUnit.Case

  alias Needy.Assistant
  alias Needy.Example.{Log, Loop, Sequence}

  describe "start/2" do
    setup :default

    test "starts all dependencies" do
      assert {:ok, pid} = Assistant.start(Loop)
      assert is_pid(pid)
      assert Assistant.status(Log) == :running
      assert Assistant.status(Loop) == :running
      assert Assistant.status(Sequence) == :running
    end

    test "does nothing if already running" do
      Assistant.start(Log)
      assert Assistant.start(Log) == nil
    end
  end

  describe "stop/2" do
    setup :default

    test "stops if possible" do
      Assistant.start(Loop)
      assert :ok = Assistant.stop(Loop)
      assert Assistant.status(Log) == :running
      assert Assistant.status(Loop) == :stopped
      assert Assistant.status(Sequence) == :running
    end

    test "returns an error if needed by others" do
      Assistant.start(Loop)
      assert {:error, :needed} == Assistant.stop(Log)
      assert Assistant.status(Log) != :stopped
    end
  end

  describe "can_stop?/2" do
    setup :default

    test "returns false when stopped" do
      refute Assistant.can_stop?(Log)
      refute Assistant.can_stop?(Loop)
      refute Assistant.can_stop?(Sequence)
    end

    test "returns true when running but not needed" do
      Assistant.start(Loop)
      assert Assistant.can_stop?(Loop)
    end

    test "returns false when running but needed" do
      Assistant.start(Loop)
      refute Assistant.can_stop?(Log)
      refute Assistant.can_stop?(Sequence)
    end
  end

  describe "lookup/2" do
    setup :default

    test "returns nil if stopped" do
      assert Assistant.lookup(Log) == nil
      assert Assistant.lookup(Loop) == nil
      assert Assistant.lookup(Sequence) == nil
    end

    test "returns a pid if running" do
      Assistant.start(Loop)
      assert is_pid(Assistant.lookup(Log))
      assert is_pid(Assistant.lookup(Loop))
      assert is_pid(Assistant.lookup(Sequence))
    end

    test "returns nil after started then stopped" do
      Assistant.start(Log)
      assert is_pid(Assistant.lookup(Log))
      Assistant.stop(Log)
      assert Assistant.lookup(Log) == nil
    end
  end

  describe "start_link/1" do
    test "returns an error without a supervisor" do
      assert {:error, :no_supervisor} = Assistant.start_link([])
    end

    test "server does not stop if a dependency crashes and :stop_dependent is false" do
      start_link(stop_dependents: false)

      {:ok, pid} = Assistant.start(Log)
      Assistant.start(Loop)
      Process.exit(pid, :crash)
      assert Assistant.status(Log) == :stopped
      assert Assistant.status(Loop) == :running
      assert Assistant.status(Sequence) == :running
    end

    test "server stops if a dependency crashes :stop_dependents is true" do
      start_link(stop_dependents: true)

      {:ok, pid} = Assistant.start(Log)
      Assistant.start(Loop)
      Process.exit(pid, :crash)
      assert Assistant.status(Log) == :stopped
      assert Assistant.status(Loop) == :stopped
      assert Assistant.status(Sequence) == :running
    end

    test "server restarts if a dependency crashes :restart_dependents is true" do
      start_link(stop_dependents: true, restart_dependents: true)

      {:ok, pid} = Assistant.start(Log)
      Assistant.start(Loop)
      Process.exit(pid, :crash)
      Process.sleep(100)
      assert Assistant.status(Log) == :running
      assert Assistant.status(Loop) == :running
      assert Assistant.status(Sequence) == :running
    end

    test "server does not restart if a dependency crashes and :restart_dependents is false" do
      start_link(stop_dependents: true, restart_dependents: false)

      {:ok, pid} = Assistant.start(Log)
      Assistant.start(Loop)
      Process.exit(pid, :crash)
      Process.sleep(100)
      assert Assistant.status(Log) == :stopped
      assert Assistant.status(Loop) == :stopped
      assert Assistant.status(Sequence) == :running
    end

    test "server does not restart if a dependency stops normally and :restart_dependents is true" do
      start_link(stop_dependents: true, restart_dependents: true)

      {:ok, pid} = Assistant.start(Sequence)
      Assistant.start(Loop)
      Process.exit(pid, :shutdown)
      Process.sleep(100)
      assert Assistant.status(Log) == :running
      assert Assistant.status(Loop) == :stopped
      assert Assistant.status(Sequence) == :stopped
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

    start_supervised!({Assistant, opts})
    :ok
  end
end
