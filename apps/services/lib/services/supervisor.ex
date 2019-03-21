defmodule Services.Supervisor do
  @moduledoc """
  Supervisor supervises services.

  I makes sure that dependencies are started in a correct order.
  It also makes sure a service isn't needed by another service before stopping it.
  """

  # TODO: monitor

  use DynamicSupervisor

  alias Services.{Dependencies, KV}

  require Logger

  @name __MODULE__

  @typedoc """
  The spec of a service is just a `child_spec`.
  """
  @type service_spec :: Supervisor.child_spec() | {module, term} | module

  @typedoc """
  The status of a service.

  If running, it is the pid of the service.
  """
  @type status :: :stopped | :starting | pid()

  @typedoc """
  The type returned when starting a service.
  """
  @type on_start_service :: [DynamicSupervisor.on_start_child()] | Dependencies.cyclic_error()

  @typedoc """
  The type returned when stopping a serivce.
  """
  @type on_stop_service :: :ok | {:error, :not_found} | {:error, :cannot_stop}

  @doc """
  Starts the supervisor.
  """
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(_opts) do
    with res = {:ok, _} <- DynamicSupervisor.start_link(@name, nil, name: @name),
         {:ok, _} <- DynamicSupervisor.start_child(@name, KV) do
      res
    end
  end

  @doc """
  Starts a service and any needed dependencies.
  """
  @spec start_service(service_spec()) :: on_start_service()
  def start_service(service) do
    with {:ok, deps} <- Dependencies.topological_sort(service) do
      deps
      |> Enum.map(&wait_til_not_starting/1)
      |> Enum.filter(&(get_service_status(&1) == :stopped))
      |> Enum.map(&do_start_service/1)
    end
  end

  @doc """
  Stops a service.
  """
  @spec stop_service(service_spec()) :: on_stop_service()
  def stop_service(service) do
    service = Supervisor.child_spec(service, [])

    stop_service(service, service_can_stop?(service))
  end

  @doc """
  Stops all services.
  """
  @spec stop_all_services() :: :ok
  def stop_all_services() do
    with stoppable = [_ | _] <- get_stoppable_services() do
      Enum.each(stoppable, &stop_service/1)
      stop_all_services()
    else
      _ -> :ok
    end
  end

  @doc """
  Returns the pid of a service.
  """
  @spec get_service_pid(service_spec()) :: pid() | nil
  def get_service_pid(service) do
    service = Supervisor.child_spec(service, [])

    status = get_service_status(service)
    if is_pid(status), do: status
  end

  @doc """
  Returns the status of a service.
  """
  @spec get_service_status(service_spec()) :: status()
  def get_service_status(service) do
    service = Supervisor.child_spec(service, [])

    with status when status != nil <- KV.get(service) do
      status
    else
      _ -> :stopped
    end
  end

  @doc """
  Returns whether a service can be stopped.

  It returns `false` if either:
  - the service isn't running
  - another running services depends on it
  """
  @spec service_can_stop?(service_spec()) :: boolean()
  def service_can_stop?(service) do
    service = Supervisor.child_spec(service, [])

    if get_service_status(service) == :stopped do
      false
    else
      Enum.find(get_running_services(), fn s ->
        service in Services.Dependencies.get_deps(s)
      end) == nil
    end
  end

  @doc false
  @impl true
  @spec init(term()) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec do_start_service(service_spec()) :: DynamicSupervisor.on_start_child()
  defp do_start_service(service) do
    Logger.info("starting #{inspect(service)}")
    KV.put(service, :starting)

    with res = {:ok, pid} <- DynamicSupervisor.start_child(@name, service) do
      KV.put(pid, service)
      KV.put(service, pid)
      res
    end
  end

  @spec wait_til_not_starting(service_spec()) :: service_spec()
  defp wait_til_not_starting(service) do
    wait_til_not_starting(service, get_service_status(service))
  end

  @spec wait_til_not_starting(service_spec(), status()) :: service_spec()
  defp wait_til_not_starting(service, :starting) do
    wait_til_not_starting(service)
  end

  defp wait_til_not_starting(service, _status) do
    service
  end

  @spec stop_service(service_spec(), boolean()) :: on_stop_service()
  defp stop_service(_service, false) do
    {:error, :cannot_stop}
  end

  defp stop_service(service, true) do
    Logger.info("stopping #{inspect(service)}")
    pid = get_service_pid(service)

    with :ok <- DynamicSupervisor.terminate_child(@name, pid) do
      KV.delete(pid)
      KV.delete(service)
      :ok
    end
  end

  @spec get_running_services() :: [{service_spec(), status()}]
  defp get_running_services() do
    children = DynamicSupervisor.which_children(@name)

    for {_, pid, _, [module]} when module != KV <- children do
      if is_pid(pid) do
        KV.get(pid)
      else
        get_running_services()
      end
    end
  end

  @spec get_stoppable_services() :: [service_spec()]
  defp get_stoppable_services() do
    Enum.filter(get_running_services(), &service_can_stop?/1)
  end
end
