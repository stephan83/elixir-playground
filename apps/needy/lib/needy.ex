defmodule Needy do
  @moduledoc """
  Needy helps dealing with server dependencies.

  A server specifies which servers it needs. When `Needy` starts a server, it makes sure all
  needed dependencies are started in correct order (using topological sort). Similarly it prevents
  stopping a server if it is needed by other running servers.

  ### Example

  Say you have a server that outputs log messages:

      defmodule Log do
        use GenServer

        require Logger

        @name __MODULE__

        def info(msg), do: GenServer.cast(@name, {:info, msg})

        @impl true
        def start_link(_opts), do: GenServer.start(@name, nil, name: @name)

        @impl true
        def init(_), do: {:ok, nil}

        @impl true
        def handle_cast({:info, msg}, _) do
          Logger.info(msg)
          {:noreply, nil}
        end
      end

  Then you can define another server that depends on it:

      defmodule Service do
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

  Now you can start the server:

      sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
      start_supervised!({Needy, supervisor: sup})
      Needy.start(SequenceService)

  The service it depends on will automatically be started.
  """

  use GenServer

  alias Needy.Dependencies

  require Logger

  @name __MODULE__

  @type server :: GenServer.server()
  @type spec :: Dependencies.spec()
  @type on_start :: Supervisor.on_start_child() | Dependencies.cyclic_error()
  @type on_stop :: :ok | {:error, :not_found} | {:error, :needed}
  @type status :: :exiting | :running | :stopped

  # Public API

  @doc """
  Starts a GenServer for Needy.

  The `supervisor` option must be a `DynamicSupervisor`.
  """
  @spec start_link(supervisor: pid) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(@name, opts, name: Keyword.get(opts, :name, @name))
  end

  @doc """
  Starts a server and its dependencies.
  """
  @spec start(server, spec) :: on_start
  def start(needy \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(needy, {:start, spec})
  end

  @doc """
  Stops a server.

  It will fail if the server is needed by other running servers.
  """
  @spec stop(server, spec) :: on_stop
  def stop(needy \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(needy, {:stop, spec})
  end

  @doc """
  Returns whether the services can be stopped.

  It returns false if the server is not running or is needed by other running servers.
  """
  @spec can_stop?(server, spec) :: boolean
  def can_stop?(needy \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(needy, {:can_stop?, spec})
  end

  @doc """
  Looks up a server by spec.
  """
  @spec lookup(server, spec) :: server | nil
  def lookup(needy \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(needy, {:pid, spec})
  end

  @doc """
  Gets the status of a server.
  """
  @spec status(server, spec) :: status
  def status(needy \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(needy, {:status, spec})
  end

  @doc false
  @impl true
  def init(opts) do
    supervisor = Keyword.get(opts, :supervisor, {DynamicSupervisor, strategy: :one_for_one})
    specs = %{}
    refs = %{}
    {:ok, {supervisor, specs, refs}}
  end

  # Server Callbacks

  @doc false
  @impl true
  def handle_call({:start, spec}, _from, state) do
    {res, state} = do_start(spec, state)
    {:reply, res, state}
  end

  @doc false
  @impl true
  def handle_call({:stop, spec}, _from, state) do
    {:reply, do_stop(spec, state), state}
  end

  @doc false
  @impl true
  def handle_call({:can_stop?, spec}, _from, state) do
    {:reply, do_can_stop?(spec, state), state}
  end

  @doc false
  @impl true
  def handle_call({:pid, spec}, _from, {_supervisor, specs, _refs} = state) do
    {:reply, Map.get(specs, spec), state}
  end

  @doc false
  @impl true
  def handle_call({:status, spec}, _from, state) do
    {:reply, do_status(spec, state), state}
  end

  @doc false
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {supervisor, specs, refs}) do
    {spec, refs} = Map.pop(refs, ref)
    specs = Map.delete(specs, spec)
    {:noreply, {supervisor, specs, refs}}
  end

  @doc false
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp do_start(spec, state) do
    with {:ok, deps} <- Dependencies.topological_sort(spec) do
      deps
      |> Enum.filter(&filter_stopped(&1, state))
      |> Enum.reduce_while({nil, state}, &reduce_start/2)
    end
  end

  defp do_stop(spec, {supervisor, specs, _} = state) do
    Logger.info("stopping #{inspect(spec)}")

    if do_can_stop?(spec, state) do
      pid = Map.get(specs, spec)
      DynamicSupervisor.terminate_child(supervisor, pid)
    else
      {:error, :needed}
    end
  end

  defp do_can_stop?(spec, {_, specs, _} = state) do
    if do_status(spec, state) == :stopped do
      false
    else
      specs
      |> Map.keys()
      |> Enum.map(&Dependencies.get_deps/1)
      |> Enum.find(&Enum.member?(&1, spec))
      |> is_nil()
    end
  end

  defp do_status(spec, {_, specs, _}) do
    with pid when is_pid(pid) <- Map.get(specs, spec) do
      case Process.info(pid, :status) do
        {:status, :exiting} -> :exiting
        {:status, :garbage_collecting} -> :running
        {:status, :waiting} -> :running
        {:status, :running} -> :running
        {:status, :runnable} -> :running
        # TODO: What does it really mean?
        {:status, :suspended} -> :running
        nil -> :stopped
      end
    else
      _ -> :stopped
    end
  end

  defp filter_stopped(spec, state) do
    case do_status(spec, state) do
      :stopped -> true
      :running -> false
      _ -> filter_stopped(spec, state)
    end
  end

  defp reduce_start(spec, {_prev, {supervisor, specs, refs} = state}) do
    Logger.info("starting #{inspect(spec)}")

    with {:ok, pid} <- DynamicSupervisor.start_child(supervisor, spec) do
      specs = Map.put(specs, spec, pid)
      ref = Process.monitor(pid)
      refs = Map.put(refs, ref, spec)
      {:cont, {{:ok, pid}, {supervisor, specs, refs}}}
    else
      err -> {:halt, {err, state}}
    end
  end
end
