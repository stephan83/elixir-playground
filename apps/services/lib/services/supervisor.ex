defmodule Services.Supervisor do
  @moduledoc """
  Supervisor supervises services.

  I makes sure that dependencies are started in a correct order.
  It also makes sure a service isn't needed by another service before stopping it.
  """

  use DynamicSupervisor

  require Logger

  @name __MODULE__

  @typedoc """
  The status of a service.

  If running, it is the pid of the service.
  """
  @type status :: :stopped | :starting | pid()

  @doc """
  Starts the supervisor.
  """
  @spec start_link(term) :: Supervisor.on_start()
  def start_link(_ \\ nil) do
    DynamicSupervisor.start_link(@name, nil, name: @name)
  end

  @doc """
  Starts a service and any needed dependencies.
  """
  @spec start_service(module()) :: [DynamicSupervisor.on_start_child()]
  def start_service(service) do
    Services.Dependencies.topological_sort(service)
    |> Enum.map(&wait_til_not_starting/1)
    |> Enum.filter(&(get_service_status(&1) == :stopped))
    |> Enum.map(&do_start_service/1)
  end

  @doc """
  Stops a service.
  """
  @spec stop_service(module()) :: :ok | {:error, :not_found} | {:error, :cannot_stop}
  def stop_service(service) do
    do_stop_service(service, can_service_stop(service))
  end

  @doc """
  Returns the pid of a service.
  """
  @spec get_service_pid(module()) :: pid() | nil
  def get_service_pid(service) do
    Enum.find_value(get_children(), fn child ->
      case child do
        {^service, status} when is_pid(status) -> status
        _ -> nil
      end
    end)
  end

  @doc """
  Returns the status of a service.
  """
  @spec get_service_status(module()) :: status()
  def get_service_status(service) do
    find_status = fn child ->
      case child do
        {^service, status} -> status
        _ -> nil
      end
    end

    Enum.find_value(get_children(), find_status) || :stopped
  end

  @doc """
  Returns whether a service can be stopped.

  It returns `false` if either:
  - the service isn't running
  - another running services depends on it
  """
  @spec can_service_stop(module()) :: boolean()
  def can_service_stop(service) do
    needed_by =
      get_children()
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.filter(&(&1 != service))
      |> Enum.find(&(service in apply(&1, :needs, [])))

    needed_by == nil and get_service_pid(service) != nil
  end

  @impl true
  @spec init(term()) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec do_start_service(module()) :: DynamicSupervisor.on_start_child()
  defp do_start_service(service) do
    Logger.info("starting #{inspect(service)}")

    DynamicSupervisor.start_child(@name, %{
      id: service,
      start: {service, :start_link, []},
      restart: :transient
    })
  end

  @spec wait_til_not_starting(module()) :: module()
  defp wait_til_not_starting(service) do
    wait_til_not_starting(service, get_service_status(service))
  end

  @spec wait_til_not_starting(module(), status()) :: module()
  defp wait_til_not_starting(service, :starting) do
    :timer.sleep(100)
    wait_til_not_starting(service)
  end

  defp wait_til_not_starting(service, _status) do
    service
  end

  @spec do_stop_service(module(), boolean()) :: :ok | {:error, atom()}
  defp do_stop_service(_service, false) do
    {:error, :cannot_stop}
  end

  defp do_stop_service(service, true) do
    Logger.info("stopping #{inspect(service)}")
    pid = get_service_pid(service)
    DynamicSupervisor.terminate_child(@name, pid)
  end

  @spec get_children() :: [{module(), status()}]
  defp get_children() do
    children = DynamicSupervisor.which_children(@name)

    Enum.map(children, fn {_, status, _, [service]} ->
      {service, convert_child_status(status)}
    end)
  end

  @spec convert_child_status(term()) :: status()
  defp convert_child_status(status) when is_pid(status), do: status
  defp convert_child_status(_status), do: :starting
end
