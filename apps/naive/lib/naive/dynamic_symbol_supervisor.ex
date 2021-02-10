defmodule Naive.DynamicSymbolSupervisor do
  use DynamicSupervisor

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Naive.{Repo, Schema, SymbolSupervisor}

  def start_link(init_arg) do
    DynamicSupervisor.start_link(
      __MODULE__,
      init_arg,
      name: __MODULE__
    )
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_trading(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.info("Starting trading on #{symbol}")
        {:ok, _settings} = update_trading_status(symbol, "on")
        {:ok, _pid} = start_symbol_supervisor(symbol)

      pid ->
        Logger.warn("Trading on #{symbol} already started")
        {:ok, settings} = update_trading_status(symbol, "on")
        Naive.Leader.notify(:settings_updated, settings)
        {:ok, pid}
    end
  end

  def stop_trading(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.warn("Trading on #{symbol} already stopped")
        {:ok, _settings} = update_trading_status(symbol, "off")

      pid ->
        Logger.info("Stopping trading on #{symbol}")

        :ok = DynamicSupervisor.terminate_child(
          Naive.DynamicSymbolSupervisor,
          pid
        )

        {:ok, _settings} = update_trading_status(symbol, "off")
    end
  end

  def shutdown_trading(symbol) when is_binary(symbol) do
    symbol = String.upcase(symbol)

    case get_pid(symbol) do
      nil ->
        Logger.warn("Trading on #{symbol} already stopped")
        {:ok, _settings} = update_trading_status(symbol, "off")

      _pid ->
        Logger.warn("Shutdown of trading on #{symbol} initialized")
        {:ok, settings} = update_trading_status(symbol, "shutdown")
        Naive.Leader.notify(:settings_updated, settings)
        {:ok, settings}
    end
  end

  def autostart_symbols() do
    Enum.map(fetch_symbols_to_trade(), &start_symbol_supervisor/1)
  end

  defp get_pid(symbol) do
    Process.whereis(:"#{SymbolSupervisor}-#{symbol}")
  end

  defp update_trading_status(symbol, status) when is_binary(symbol) and is_binary(status) do
    Schema.Settings
    |> Repo.get_by(symbol: symbol)
    |> Ecto.Changeset.change(%{status: status})
    |> Repo.update()
  end

  defp fetch_symbols_to_trade do
    (s in Schema.Settings)
    |> from(where: s.status == "on", select: s.symbol)
    |> Repo.all()
  end

  defp start_symbol_supervisor(symbol) do
    DynamicSupervisor.start_child(
      Naive.DynamicSymbolSupervisor,
      {Naive.SymbolSupervisor, symbol}
    )
  end
end