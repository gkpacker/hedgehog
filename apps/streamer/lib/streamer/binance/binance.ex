defmodule Streamer.Binance do
  use WebSockex

  require Logger

  @stream_endpoint "wss://stream.binance.com:9443/ws/"

  defmodule State do
    @enforce_keys [:symbol]
    defstruct [:symbol]
  end

  def start_link(symbol) do
    symbol = String.downcase(symbol)
    url = "#{@stream_endpoint}#{symbol}@trade"

    Logger.info("Starting streaming on #{symbol}")
    Logger.debug(url)

    WebSockex.start_link(
      url,
      __MODULE__,
      %State{symbol: symbol},
      name: :"#{__MODULE__}-#{symbol}"
    )
  end

  def handle_frame({_type, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} -> process_event(event, state.symbol)
      {:error, _} -> Logger.error("Unable to parse msg: #{msg}")
    end

    {:ok, state}
  end

  @doc """
  https://github.com/binance/binance-spot-api-docs/blob/master/web-socket-streams.md#trade-streams
  """
  def process_event(%{"e" => "trade"} = event, symbol) do
    trade_event = %Streamer.Binance.TradeEvent{
      event_type: event["e"],
      event_time: event["E"],
      symbol: event["s"],
      trade_id: event["t"],
      price: event["p"],
      quantity: event["q"],
      buyer_order_id: event["b"],
      seller_order_id: event["a"],
      trade_time: event["T"],
      buyer_market_maker: event["m"]
    }

    Logger.debug(
      "Trade event received " <>
        "#{trade_event.symbol}@#{trade_event.price}"
    )

    Phoenix.PubSub.broadcast(
      Streamer.PubSub,
      "trade_events:#{symbol}",
      trade_event
    )
  end
end
