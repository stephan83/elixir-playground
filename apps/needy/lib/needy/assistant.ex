defmodule Needy.Assistant do
  @moduledoc """
  An assistant helps a `DynamicSupervisor` deal with process dependencies.

  A module specifies which processes it needs. When `Assistant` starts a `child_spec`, it makes
  sure all needed processes are started in correct order (using topological sort). Similarly it
  prevents stopping a process if it is needed by other running processes.

  To declare that a module has depedendencies, it should export a `needs` function that returns
  a list of `child_spec`. Its arity can be either zero or the same as the `start_link` function,
  in which case it will receive the same arguments.

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

      defmodule Sequence do
        use Agent, restart: :temporary

        @name __MODULE__

        @impl true
        def start_link(_opts), do: Agent.start_link(fn -> 0 end, name: @name)

        @impl true
        def needs(_opts), do: [Log]

        def next do
          Log.info("Next number requested")
          Agent.get_and_update(@name, &{&1, &1 + 1})
        end
      end

  To run, start a `DynamicSupervisor` and pass it to `Assistant`. Now launch children using
  `start/2`.

      sup = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
      opts = [supervisor: sup, stop_dependents: true, restart_dependents: true]
      start_supervised!({assistant.Assistant, opts})
      assistant.start(Sequence)

  The processes it depends on will automatically be started.
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

  defmodule State do
    @moduledoc false

    alias Needy.{Assistant, Dependencies}

    defstruct [
      :supervisor,
      specs: %{},
      refs: %{},
      stop_dependents: false,
      restart_dependents: false
    ]

    @type t :: %__MODULE__{
            supervisor: Assistant.server(),
            specs: %{optional(Dependencies.child_spec()) => pid},
            refs: %{optional(reference) => Dependencies.child_spec()},
            stop_dependents: boolean,
            restart_dependents: boolean
          }
  end

  # ==============================================================================================
  # Client API
  # ==============================================================================================

  @doc """
  Starts the server.

  The `supervisor` option is mandatory and must be a `DynamicSupervisor`.

  The other options are:

  - stop_dependents: stop all dependents when a process stops (default `false`)
  - restart_dependents: restart all dependents when a process unexpectedly stops (default `false`)

  If either `stop_dependents` or `restart_dependents` are true, it makes sense for processes to
  be started with a `:temporary` restart policy, otherwise it will conflict with the
  `DynamicSupervisor`.
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

    state = Map.merge(%State{}, opts)

    {:ok, state}
  end

  @doc """
  Starts a process and its dependencies.

  It returns `nil` if no processes needed to be started.
  """
  @spec start(server, spec) :: on_start
  def start(assistant \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(assistant, {:start, spec})
  end

  @doc """
  Stops a process.

  It will fail if the process is needed by other running processes.
  """
  @spec stop(server, spec) :: on_stop
  def stop(assistant \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(assistant, {:stop, spec})
  end

  @doc """
  Returns whether the process can be stopped.

  It returns false if the process is not running or is needed by other running processes.
  """
  @spec can_stop?(server, spec) :: boolean
  def can_stop?(assistant \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(assistant, {:can_stop?, spec})
  end

  @doc """
  Looks up a process by spec.
  """
  @spec lookup(server, spec) :: server | nil
  def lookup(assistant \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(assistant, {:lookup, spec})
  end

  @doc """
  Gets the status of a process.
  """
  @spec status(server, spec) :: status
  def status(assistant \\ @name, spec) do
    spec = Supervisor.child_spec(spec, [])
    GenServer.call(assistant, {:status, spec})
  end

  # ==============================================================================================
  # Server Callbacks
  # ==============================================================================================

  @spec handle_call(term, GenServer.from(), State.t()) :: {:reply, term, State.t()}

  @doc false
  @impl true
  def handle_call({:start, spec}, _from, %State{} = state) do
    {res, state} = do_start(spec, state)
    {:reply, res, state}
  end

  @doc false
  @impl true
  def handle_call({:stop, spec}, _from, %State{} = state) do
    {:reply, do_stop(spec, state), state}
  end

  @doc false
  @impl true
  def handle_call({:can_stop?, spec}, _from, %State{} = state) do
    {:reply, do_can_stop?(spec, state), state}
  end

  @doc false
  @impl true
  def handle_call({:lookup, spec}, _from, %State{specs: specs} = state) do
    {:reply, Map.get(specs, spec), state}
  end

  @doc false
  @impl true
  def handle_call({:status, spec}, _from, %State{} = state) do
    {:reply, do_status(spec, state), state}
  end

  @spec handle_info(:timeout | term, State.t()) :: {:noreply, State.t()}

  @doc false
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{} = state) do
    {spec, refs} = Map.pop(state.refs, ref)

    if state.stop_dependents do
      stop_dependents(spec, state, reason)
    end

    specs = Map.delete(state.specs, spec)
    state = %State{state | specs: specs, refs: refs}

    if reason not in [:normal, :shutdown] and state.restart_dependents do
      {_res, state} = do_start(spec, state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @doc false
  @impl true
  def handle_info(_msg, %State{} = state) do
    {:noreply, state}
  end

  # ==============================================================================================
  # Internals
  # ==============================================================================================

  @spec do_start(Dependencies.child_spec(), State.t()) :: {on_start, State.t()}
  defp do_start(spec, %State{} = state) do
    with {:ok, deps} <- Dependencies.dependencies(spec) do
      deps
      |> Enum.filter(&filter_stopped(&1, state))
      |> Enum.reduce_while({nil, state}, &start_reducer/2)
    else
      err -> {err, state}
    end
  end

  @spec do_stop(Dependencies.child_spec(), State.t()) :: on_stop
  defp do_stop(spec, %State{supervisor: supervisor, specs: specs} = state) do
    Logger.info("stopping #{inspect(spec)}")

    if do_can_stop?(spec, state) do
      pid = Map.get(specs, spec)
      DynamicSupervisor.terminate_child(supervisor, pid)
    else
      {:error, :needed}
    end
  end

  @spec do_can_stop?(Dependencies.child_spec(), State.t()) :: boolean
  defp do_can_stop?(spec, %State{specs: specs} = state) do
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

  @spec do_status(Dependencies.child_spec(), State.t()) :: status
  defp do_status(spec, %State{specs: specs}) do
    with pid when is_pid(pid) <- Map.get(specs, spec) do
      case Process.info(pid, :status) do
        {:status, :exiting} -> :exiting
        {:status, :garbage_collecting} -> :running
        {:status, :waiting} -> :running
        {:status, :running} -> :running
        {:status, :runnable} -> :running
        {:status, :suspended} -> :running
        nil -> :stopped
      end
    else
      _ -> :stopped
    end
  end

  @spec filter_stopped(Dependencies.child_spec(), State.t()) :: boolean
  defp filter_stopped(spec, %State{} = state) do
    case do_status(spec, state) do
      :stopped -> true
      :running -> false
      _ -> filter_stopped(spec, state)
    end
  end

  @typep start_reducer_success :: {{:ok, pid}, State.t()}
  @typep start_reducer_error :: {{:error, term}, State.t()}
  @spec start_reducer(Dependencies.child_spec(), start_reducer_success) ::
          {:cont, start_reducer_success}
          | {:halt, start_reducer_error}
  defp start_reducer(spec, {_last, %State{} = state} = acc) do
    Logger.info("starting #{inspect(spec)}")

    case DynamicSupervisor.start_child(state.supervisor, spec) do
      {:ok, pid} ->
        {:cont, {{:ok, pid}, add_child(spec, pid, state)}}

      {:ok, pid, _} ->
        {:cont, {{:ok, pid}, add_child(spec, pid, state)}}

      :ignore ->
        {:cont, acc}

      err ->
        {:halt, {err, state}}
    end
  end

  @spec add_child(Dependencies.child_spec(), pid, State.t()) :: State.t()
  defp add_child(spec, pid, %State{specs: specs, refs: refs} = state) do
    specs = Map.put(specs, spec, pid)
    ref = Process.monitor(pid)
    refs = Map.put(refs, ref, spec)
    %State{state | specs: specs, refs: refs}
  end

  @spec stop_dependents(Dependencies.child_spec(), State.t(), atom) :: :ok
  defp stop_dependents(spec, %State{specs: specs}, reason) do
    all_specs = Map.keys(specs)
    {:ok, dependents} = Dependencies.dependents(spec, all_specs)

    dependents
    |> Enum.map(&Map.get(specs, &1))
    |> Enum.each(&Process.exit(&1, reason))
  end
end
