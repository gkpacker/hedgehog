defmodule Naive.Trader do
  use GenServer

  require Logger

  alias Decimal, as: D
  alias Streamer.Binance.TradeEvent

  @filter_type "PRICE_FILTER"

  defmodule State do
    @enforce_keys [:symbol, :profit_interval, :tick_size]

    defstruct [
      :symbol,
      :buy_order,
      :sell_order,
      :profit_interval,
      :tick_size
    ]
  end

  def start_link(%{} = args) do
    GenServer.start_link(__MODULE__, args, name: :trader)
  end

  def init(%{} = args) do
    tick_size = fetch_tick_size(args.symbol)

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "trade_events:#{symbol}"
    )

    {:ok,
     %State{
       symbol: args.symbol,
       profit_interval: args.profit_interval,
       tick_size: tick_size
     }}
  end

  def handle_info(
        %TradeEvent{price: price},
        %State{symbol: symbol, buy_order: nil} = state
      ) do
    Logger.info("Placing buy order (#{symbol}@#{price})")

    quantity = 100

    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_buy(
        symbol,
        quantity,
        price,
        "GTC"
      )

    {:noreply, %{state | buy_order: order}}
  end

  def handle_info(
        %TradeEvent{buyer_order_id: order_id, quantity: quantity},
        %State{
          symbol: symbol,
          buy_order: %Binance.OrderResponse{
            price: buy_price,
            order_id: order_id,
            orig_qty: orig_qty
          },
          profit_interval: profit_interval,
          tick_size: tick_size
        } = state
      ) do
    sell_price =
      calculate_sell_price(
        buy_price,
        profit_interval,
        tick_size
      )

    Logger.info("Buy order filled, placing sell order (#{symbol}@#{sell_price})")

    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_sell(
        symbol,
        quantity,
        sell_price,
        "GTC"
      )

    {:noreply, %{state | sell_order: order}}
  end

  def handle_info(
        %TradeEvent{seller_order_id: order_id, quantity: quantity},
        %State{
          sell_order: %Binance.OrderResponse{
            order_id: order_id,
            orig_qty: orig_qty
          }
        } = state
      ) do
    Logger.info("Trade finished, trader will now exit")

    {:stop, :normal, state}
  end

  def handle_info(%TradeEvent{}, state) do
    {:noreply, state}
  end

  defp fetch_tick_size(symbol) do
    Binance.get_exchange_info()
    |> elem(1)
    |> Map.get(:symbols)
    |> Enum.find(&(&1["symbol"] == String.upcase(symbol)))
    |> Map.get("filters")
    |> Enum.find(&(&1["filterType"] == @filter_type))
    |> Map.get("tickSize")
  end

  defp calculate_sell_price(
         buy_price,
         profit_interval,
         tick_size
       ) do
    fee = D.cast("1.001")
    original_price = buy_price |> D.cast() |> D.mult(fee)
    tick = D.cast(tick_size)

    new_target_price =
      D.mult(
        original_price,
        D.add("1.0", D.cast(profit_interval))
      )

    gross_target_price =
      D.mult(
        new_target_price,
        fee
      )

    gross_target_price
    |> D.div_int(tick)
    |> D.mult(tick)
    |> D.to_float()
  end
end
