defmodule Core.ServiceSupervisor do
  require Logger

  defmacro __using__(opts) do
    {:ok, settings_repo} = Keyword.fetch(opts, :settings_repo)
    {:ok, module} = Keyword.fetch(opts, :module)
    {:ok, worker_module} = Keyword.fetch(opts, :worker_module)

    quote location: :keep do
      use DynamicSupervisor

      def autostart_workers() do
        Core.ServiceSupervisor.autostart_workers(
          unquote(settings_repo),
          unquote(module),
          unquote(worker_module)
        )
      end

      def start_worker(symbol) do
        Core.ServiceSupervisor.start_worker(
          symbol,
          unquote(settings_repo),
          unquote(module),
          unquote(worker_module)
        )
      end

      def stop_worker(symbol) do
        Core.ServiceSupervisor.stop_worker(
          symbol,
          unquote(settings_repo),
          unquote(module),
          unquote(worker_module)
        )
      end

      def get_pid(symbol) do
        Core.ServiceSupervisor.get_pid(unquote(worker_module), symbol)
      end
    end
  end

  defdelegate start_link(module, args, opts), to: DynamicSupervisor
  defdelegate init(opts), to: DynamicSupervisor

  def autostart_workers(settings_repo, module, worker_module) do
    started_symbols = settings_repo.started_symbols()

    Enum.map(started_symbols, &start_worker(&1, settings_repo, module, worker_module))
  end

  def start_worker(symbol, settings_repo, module, worker_module) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(worker_module, symbol) do
      nil ->
        Logger.info("Starting #{worker_module} on #{symbol}")
        {:ok, _settings} = settings_repo.start(symbol)
        {:ok, _pid} = DynamicSupervisor.start_child(module, {worker_module, symbol})

      pid ->
        Logger.warn("#{worker_module} worker for #{symbol} already started")
        {:ok, settings} = settings_repo.start(symbol)
        module.notifier().notify(:settings_updated, settings)
        {:ok, pid}
    end
  end

  def stop_worker(symbol, settings_repo, module, worker_module) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(worker_module, symbol) do
      nil ->
        Logger.warn("#{worker_module} worker for #{symbol} already stopped")
        {:ok, _settings} = settings_repo.stop(symbol)

      pid ->
        Logger.info("Stopping #{worker_module} worker for #{symbol}")

        :ok = DynamicSupervisor.terminate_child(module, pid)

        {:ok, _settings} = settings_repo.stop(symbol)
    end
  end

  def get_pid(worker_module, symbol) do
    symbol = String.upcase(symbol)

    Process.whereis(:"#{worker_module}-#{symbol}")
  end
end
