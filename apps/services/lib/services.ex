defmodule Services do
  @moduledoc """
  Services contains types to work with services.

  ### Example

  Below illutatrates how to create and start a simple service using an `Agent` that depends on
  another service called `LogService`.

      defmodule SequenceService do
        use Services.Service
        use Agent, restart: :transient

        @name __MODULE__

        @impl
        def start_link(), do: Agent.start_link(fn -> 0 end, name: @name)

        @impl
        def needs(), do: [LogService]

        def next do
          LogService.info("Next number requested")
          Agent.get_and_update(@name, &{&1, &1 + 1})
        end
      end

      Services.Supervisor.start_service(SequenceService)
  """
end
