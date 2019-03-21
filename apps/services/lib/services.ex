defmodule Services do
  @moduledoc """
  Services contains types to work with services.

  A service specifies which services it needs. When `Services.Supervisor` starts a service,
  it makes sure all needed dependencies are started in correct order (using topological sort).
  Similarly it prevents stopping a service if it is needed by other running services.

  ### Example

  Say you have a service that outputs log messages:

      defmodule Log do
        use Services.Service
        use GenServer

        require Logger

        @name __MODULE__

        @impl true
        def start_link(_opts), do: GenServer.start(@name, nil, name: @name)

        @impl true
        def init(_), do: {:ok, nil}

        def info(msg), do: GenServer.cast(@name, {:info, msg})

        @impl true
        def handle_cast({:info, msg}, _) do
          Logger.info(msg)
          {:noreply, nil}
        end
      end

  Then you can define another service that depends on it:

      defmodule Service do
        use Services.Service
        use Agent

        @name __MODULE__

        @impl true
        def start_link(_opts), do: Agent.start_link(fn -> 0 end, name: @name)

        @impl true
        def needs(_opts), do: [Log]

        def next do
          LogService.info("Next number requested")
          Agent.get_and_update(@name, &{&1, &1 + 1})
        end
      end

  Now you can start the service:

      Services.Supervisor.start_service(SequenceService)

  The service it depends on will automatically be started.
  """
end
