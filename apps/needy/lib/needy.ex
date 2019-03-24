defmodule Needy do
  @moduledoc """
  Needy helps dealing with server dependencies.

  A server specifies which servers it needs. When `Needy` starts a server, it makes sure all
  needed dependencies are started in correct order (using topological sort). Similarly it prevents
  stopping a server if it is needed by other running servers.

  ### Example

  Say you have a server that outputs log messages:

      defmodule Log do
        use GenServer, restart: :temporary

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
        use Agent, restart: :temporary

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
      start_supervised!({Needy, supervisor: sup, stop_dependents: true, restart_dependents: true})
      Needy.start(SequenceService)

  The service it depends on will automatically be started.
  """

  use GenServer

  alias Needy.Dependencies

  require Logger

  @name __MODULE__
  @opts [:supervisor, :stop_dependents, :restart_dependents]
  @default_opts stop_dependents: false, restart_dependents: false

  @type server :: GenServer.server()
  @type spec :: Dependencies.spec()
  @type on_start :: Supervisor.on_start_child() | Dependencies.cyclic_error() | nil
  @type on_stop :: :ok | {:error, :not_found} | {:error, :needed}
  @type status :: :exiting | :running | :stopped

  # Client API

  @doc """
  Starts a GenServer for Needy.

  The `supervisor` option is mandatory and must be a `DynamicSupervisor`.

  The other options are:

  - stop_dependents: stop all dependents when a process stops (default `false`)
  - restart_dependents: stop all dependents when a process unexpectedly stops (default `false`)
  """
  @spec start_link(supervisor: pid) :: GenServer.on_start() | {:error, :no_supervisor}
  def start_link(opts) do
    if Keyword.get(opts, :supervisor) do
      GenServer.start_link(@name, opts, name: Keyword.get(opts, :name, @name))
    else
      {:error, :no_supervisor}
    end
  end

  @doc false
  @impl true
  def init(opts) do
    opts =
      @default_opts
      |> Keyword.merge(opts)
      |> Keyword.take(@opts)
      |> Enum.into(%{})

    {:ok, {%{}, %{}, opts}}
  end

  @doc """
  Starts a server and its dependencies.

  It returns `nil` if no servers needed to be started.
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
    GenServer.call(needy, {:lookup, spec})
  end

  @doc """
  Gets the status of a server.
  """
  @spec status(server, spec) :: status
  def status(needy \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(needy, {:status, spec})
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
  def handle_call({:lookup, spec}, _from, {specs, _refs, _opts} = state) do
    {:reply, Map.get(specs, spec), state}
  end

  @doc false
  @impl true
  def handle_call({:status, spec}, _from, state) do
    {:reply, do_status(spec, state), state}
  end

  @doc false
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, {specs, refs, opts} = state) do
    {spec, refs} = Map.pop(refs, ref)

    if opts.stop_dependents do
      stop_dependents(spec, state, reason)
    end

    specs = Map.delete(specs, spec)
    state = {specs, refs, opts}

    if reason not in [:normal, :shutdown] and opts.restart_dependents do
      {_res, state} = do_start(spec, state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @doc false
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp do_start(spec, state) do
    with {:ok, deps} <- Dependencies.dependencies(spec) do
      deps
      |> Enum.filter(&filter_stopped(&1, state))
      |> Enum.reduce_while({nil, state}, &start_reducer/2)
    else
      err -> {err, state}
    end
  end

  defp do_stop(spec, {specs, _refs, opts} = state) do
    Logger.info("stopping #{inspect(spec)}")

    if do_can_stop?(spec, state) do
      pid = Map.get(specs, spec)
      DynamicSupervisor.terminate_child(opts.supervisor, pid)
    else
      {:error, :needed}
    end
  end

  defp do_can_stop?(spec, {specs, _refs, _opts} = state) do
    if do_status(spec, state) == :stopped do
      false
    else
      specs
      |> Map.keys()
      |> Enum.map(&Dependencies.needs/1)
      |> Enum.find(&Enum.member?(&1, spec))
      |> is_nil()
    end
  end

  defp do_status(spec, {specs, _refs, _opts}) do
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

  defp start_reducer(spec, {_last, {specs, refs, opts} = state}) do
    Logger.info("starting #{inspect(spec)}")

    with {:ok, pid} <- DynamicSupervisor.start_child(opts.supervisor, spec) do
      specs = Map.put(specs, spec, pid)
      ref = Process.monitor(pid)
      refs = Map.put(refs, ref, spec)
      {:cont, {{:ok, pid}, {specs, refs, opts}}}
    else
      err -> {:halt, {err, state}}
    end
  end

  defp stop_dependents(spec, {specs, _refs, _opts}, reason) do
    all_specs = Map.keys(specs)
    {:ok, dependents} = Dependencies.dependents(spec, all_specs)

    dependents
    |> Enum.map(&Map.get(specs, &1))
    |> Enum.map(&Process.exit(&1, reason))
  end
end
