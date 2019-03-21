defmodule Services.SupervisorTest do
  use ExUnit.Case, async: true

  alias Services.Supervisor, as: Sup
  alias Services.Example.{Log, Loop, Sequence}

  setup do
    start_supervised!(Services.Supervisor)
    :ok
  end

  describe "start_service/1" do
    test "starts the service and its dependencies" do
      assert [{:ok, _}, {:ok, _}, {:ok, _}] = Sup.start_service(Loop)
      assert Sup.get_service_status(Log) != :stopped
      assert Sup.get_service_status(Loop) != :stopped
      assert Sup.get_service_status(Sequence) != :stopped
    end
  end

  describe "stop_service/1" do
    test "stops a service if possible" do
      Sup.start_service(Loop)
      assert Sup.stop_service(Loop) == :ok
      assert Sup.get_service_status(Loop) == :stopped
    end

    test "returns an error if the service is needed by running services" do
      Sup.start_service(Loop)
      assert {:error, :cannot_stop} == Sup.stop_service(Log)
      assert Sup.get_service_status(Log) != :stopped
    end
  end

  describe "stop_all_services/0" do
    test "stops all running services" do
      Sup.start_service(Loop)
      assert Sup.stop_all_services() == :ok
      assert Sup.get_service_status(Log) == :stopped
      assert Sup.get_service_status(Loop) == :stopped
      assert Sup.get_service_status(Sequence) == :stopped
    end
  end

  describe "service_can_stop?/1" do
    test "returns false when a service is stopped" do
      refute Sup.service_can_stop?(Log)
      refute Sup.service_can_stop?(Loop)
      refute Sup.service_can_stop?(Sequence)
    end

    test "returns true when a service is running but not needed" do
      Sup.start_service(Loop)
      assert Sup.service_can_stop?(Loop)
    end

    test "returns false when a service is running but needed" do
      Sup.start_service(Loop)
      refute Sup.service_can_stop?(Log)
      refute Sup.service_can_stop?(Sequence)
    end
  end
end
