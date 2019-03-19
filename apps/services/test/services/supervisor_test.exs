defmodule Services.SupervisorTest do
  use ExUnit.Case

  alias Services.Supervisor, as: Sup
  alias Services.Example.{Log, Loop, Sequence}

  setup do
    {:ok, _} = start_supervised(Services.Supervisor)
    :ok
  end

  describe "start_service" do
    test "starts the service and its dependencies" do
      Sup.start_service(Loop)

      assert Sup.get_service_status(Log) != :stopped
      assert Sup.get_service_status(Loop) != :stopped
      assert Sup.get_service_status(Sequence) != :stopped
    end
  end

  describe "stop_service" do
    test "stops a service if possible" do
      Sup.start_service(Loop)

      assert :ok = Sup.stop_service(Loop)
      assert Sup.get_service_status(Loop) == :stopped
    end

    test "returns an error if the service is needed" do
      Sup.start_service(Loop)

      assert {:error, :cannot_stop} == Sup.stop_service(Log)
      assert Sup.get_service_status(Log) != :stopped
    end
  end

  describe "can_service_stop" do
    test "returns false when a service is stopped" do
      assert Sup.can_service_stop(Log) == false
      assert Sup.can_service_stop(Loop) == false
      assert Sup.can_service_stop(Sequence) == false
    end

    test "returns true when a service is running but not needed" do
      Sup.start_service(Loop)

      assert Sup.can_service_stop(Loop) == true
    end

    test "returns false when a service is running but needed" do
      Sup.start_service(Loop)

      assert Sup.can_service_stop(Log) == false
      assert Sup.can_service_stop(Sequence) == false
    end
  end
end
