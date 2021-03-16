defmodule Naive.DynamicSymbolSupervisor do
  use Core.ServiceSupervisor,
    settings_repo: Naive.Settings,
    module: __MODULE__,
    worker_module: Naive.SymbolSupervisor

  require Logger

  alias Naive.Settings

  def start_link(init_arg) do
    Core.ServiceSupervisor.start_link(
      __MODULE__,
      init_arg,
      name: __MODULE__
    )
  end

  def init(_init_arg) do
    Core.ServiceSupervisor.init(strategy: :one_for_one)
  end

  def notifier, do: Naive.Leader

  def shutdown_worker(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.warn("#{Naive.SymbolSupervisor} worker for #{symbol} already stopped")
        {:ok, _settings} = Settings.stop(symbol)

      _pid ->
        Logger.warn("Initializing shutdown of #{Naive.SymbolSupervisor} worker for #{symbol}")
        {:ok, settings} = Settings.shutdown(symbol)
        notifier().notify(:settings_updated, settings)
        {:ok, settings}
    end
  end
end
