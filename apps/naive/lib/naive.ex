defmodule Naive do
  alias Streamer.Binance.TradeEvent

  def start_trading(symbol) do
    symbol = String.upcase(symbol)

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Naive.DynamicSymbolSupervisor,
        {Naive.SymbolSupervisor, symbol}
      )
  end

  def send_event(%TradeEvent{} = event) do
    GenServer.cast(:trader, event)
  end
end
