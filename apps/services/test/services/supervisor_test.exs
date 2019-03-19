defmodule Services.SupervisorTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Services.Supervisor, as: Sup
  alias Services.Example.{Log, Loop, Sequence}

  setup do
    start_supervised!(Services.Supervisor)
    :ok
  end

  describe "start_service" do
    test "starts the service and its dependencies" do
      capture_log(fn ->
        Sup.start_service(Loop)

        assert Sup.get_service_status(Log) != :stopped
        assert Sup.get_service_status(Loop) != :stopped
        assert Sup.get_service_status(Sequence) != :stopped
      end)
    end
  end

  describe "stop_service" do
    test "stops a service if possible" do
      capture_log(fn ->
        Sup.start_service(Loop)

        assert Sup.stop_service(Loop) == :ok
        assert Sup.get_service_status(Loop) == :stopped
      end)
    end

    test "returns an error if the service is needed" do
      capture_log(fn ->
        Sup.start_service(Loop)

        assert {:error, :cannot_stop} == Sup.stop_service(Log)
        assert Sup.get_service_status(Log) != :stopped
      end)
    end
  end

  describe "stop_all_services" do
    test "stops all running services" do
      capture_log(fn ->
        Sup.start_service(Loop)

        assert Sup.stop_all_services() == [:ok, :ok, :ok]
        assert Sup.get_service_status(Log) == :stopped
        assert Sup.get_service_status(Loop) == :stopped
        assert Sup.get_service_status(Sequence) == :stopped
      end)
    end
  end

  describe "service_can_stop?" do
    test "returns false when a service is stopped" do
      assert !Sup.service_can_stop?(Log)
      assert !Sup.service_can_stop?(Loop)
      assert !Sup.service_can_stop?(Sequence)
    end

    test "returns true when a service is running but not needed" do
      capture_log(fn ->
        Sup.start_service(Loop)

        assert Sup.service_can_stop?(Loop)
      end)
    end

    test "returns false when a service is running but needed" do
      capture_log(fn ->
        Sup.start_service(Loop)

        assert !Sup.service_can_stop?(Log)
        assert !Sup.service_can_stop?(Sequence)
      end)
    end
  end
end
