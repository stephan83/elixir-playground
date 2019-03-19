defmodule Services.Application do
  @moduledoc false

  use Application

  alias Services.Example.{Loop, Sequence}

  require Logger

  @impl true
  def start(_type, _args) do
    # Start the service supervisor.
    {:ok, pid} = Services.Supervisor.start_link()

    spawn(fn ->
      # Example code

      log_service_info(Loop)
      log_service_info(Sequence)

      # Start the Looper service, which automatically starts the Sequence service.
      Services.Supervisor.start_service(Loop)

      log_service_info(Loop)
      log_service_info(Sequence)

      :timer.sleep(5000)

      # Stop services.
      Services.Supervisor.stop_service(Loop)
      Services.Supervisor.stop_service(Sequence)

      log_service_info(Loop)
      log_service_info(Sequence)
    end)

    {:ok, pid}
  end

  defp log_service_info(service) do
    require Logger

    status = Services.Supervisor.get_service_status(service)
    can_stop = Services.Supervisor.can_service_stop(service)

    Logger.info(
      "#{inspect(service)} status: #{inspect(status)}, can_service_stop: #{ inspect(can_stop) }"
    )
  end
end
