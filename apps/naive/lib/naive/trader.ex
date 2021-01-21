defmodule Naive.Trader do
  use GenServer, restart: :temporary

  require Logger

  alias Decimal, as: D
  alias Streamer.Binance.TradeEvent

  @binance_client Application.get_env(:naive, :binance_client)

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

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{symbol: symbol} = state) do
    symbol = String.upcase(symbol)

    Logger.info("Initializing new trader for symbol(#{symbol})")

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "trade_events:#{symbol}"
    )

    {:ok, state}
  end

  def handle_info(
        %TradeEvent{price: price},
        %State{symbol: symbol, buy_order: nil} = state
      ) do
    Logger.info("Placing buy order (#{symbol}@#{price})")

    quantity = 100

    {:ok, %Binance.OrderResponse{} = order} =
      @binance_client.order_limit_buy(
        symbol,
        quantity,
        price,
        "GTC"
      )

    new_state = %{state | buy_order: order}

    Naive.Leader.notify(:trader_state_updated, new_state)

    {:noreply, new_state}
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
      @binance_client.order_limit_sell(
        symbol,
        quantity,
        sell_price,
        "GTC"
      )

    new_state = %{state | sell_order: order}

    Naive.Leader.notify(:trader_state_updated, new_state)

    {:noreply, new_state}
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

  def handle_info(%TradeEvent{} = event, state) do
    {:noreply, state}
  end

  defp calculate_sell_price(
         buy_price,
         profit_interval,
         tick_size
       ) do
    fee = D.from_float(1.001)
    original_price = buy_price |> D.new() |> D.mult(fee)
    tick = D.new(tick_size)

    profit_interval_decimal = D.from_float(profit_interval)

    new_target_price =
      D.mult(
        original_price,
        D.add("1.0", profit_interval_decimal)
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
