defmodule Naive.Trader do
  use GenServer, restart: :temporary

  require Logger

  alias Decimal, as: D
  alias Streamer.Binance.TradeEvent

  @binance_client Application.get_env(:naive, :binance_client)

  defmodule State do
    @enforce_keys [
      :id,
      :symbol,
      :budget,
      :buy_down_interval,
      :profit_interval,
      :rebuy_interval,
      :rebuy_notified,
      :tick_size,
      :step_size
    ]

    defstruct [
      :id,
      :symbol,
      :budget,
      :buy_order,
      :sell_order,
      :profit_interval,
      :buy_down_interval,
      :rebuy_interval,
      :rebuy_notified,
      :tick_size,
      :step_size
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
        %State{
          id: id,
          symbol: symbol,
          budget: budget,
          buy_order: nil,
          buy_down_interval: buy_down_interval,
          tick_size: tick_size,
          step_size: step_size
        } = state
      ) do
    buy_price =
      calculate_buy_price(
        price,
        buy_down_interval,
        tick_size
      )

    Logger.info("Trader(#{id}) placing buy order (#{symbol}@#{price})")

    quantity =
      calculate_quantity(
        budget,
        price,
        step_size
      )

    {:ok, %Binance.OrderResponse{} = order} =
      @binance_client.order_limit_buy(
        symbol,
        quantity,
        buy_price,
        "GTC"
      )

    new_state = %{state | buy_order: order}

    Naive.Leader.notify(:trader_state_updated, new_state)

    {:noreply, new_state}
  end

  def handle_info(
        %TradeEvent{},
        %State{
          symbol: _symbol,
          buy_order: %Binance.OrderResponse{
            order_id: _order_id,
            status: "FILLED"
          }
        } = state
      ) do
    {:noreply, state}
  end

  def handle_info(
        %TradeEvent{buyer_order_id: order_id},
        %State{
          id: id,
          symbol: symbol,
          buy_order:
            %Binance.OrderResponse{
              price: buy_price,
              order_id: order_id,
              orig_qty: quantity,
              transact_time: timestamp
            } = buy_order,
          profit_interval: profit_interval,
          tick_size: tick_size
        } = state
      ) do
    {:ok, %Binance.Order{} = current_buy_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    buy_order = %{buy_order | status: current_buy_order.status}

    {:ok, new_state} =
      if buy_order.status == "FILLED" do
        sell_price =
          calculate_sell_price(
            buy_price,
            profit_interval,
            tick_size
          )

        Logger.info(
          "Trader(#{id}) buy order filled, placing sell order (#{symbol}@#{sell_price})"
        )

        {:ok, %Binance.OrderResponse{} = new_sell_order} =
          @binance_client.order_limit_sell(
            symbol,
            quantity,
            sell_price,
            "GTC"
          )

        {:ok, %{state | buy_order: buy_order, sell_order: new_sell_order}}
      else
        {:ok, %{state | buy_order: buy_order}}
      end

    Naive.Leader.notify(:trader_state_updated, new_state)

    {:noreply, new_state}
  end

  def handle_info(
        %TradeEvent{seller_order_id: order_id},
        %State{
          id: id,
          symbol: symbol,
          sell_order:
            %Binance.OrderResponse{
              order_id: order_id,
              transact_time: timestamp
            } = sell_order
        } = state
      ) do
    {:ok, %Binance.Order{} = current_sell_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    sell_order = %{sell_order | status: current_sell_order.status}

    if sell_order.status == "FILLED" do
      Logger.info("Trader(#{id}) - Trade finished, trader will now exit")

      {:stop, :trade_finished, state}
    else
      new_state = %{state | sell_order: sell_order}

      {:noreply, new_state}
    end
  end

  def handle_info(
        %TradeEvent{price: current_price} = event,
        %State{
          id: id,
          symbol: symbol,
          buy_order: %Binance.OrderResponse{
            price: buy_price
          },
          rebuy_interval: rebuy_interval,
          rebuy_notified: false
        } = state
      ) do
    if trigger_rebuy?(buy_price, current_price, rebuy_interval) do
      Logger.info("Rebuy triggered by trader(#{id}@#{symbol})")

      new_state = %{state | rebuy_notified: true}

      Naive.Leader.notify(:rebuy_triggered, new_state)

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp trigger_rebuy?(buy_price, current_price, rebuy_interval) do
    current_price = float_to_decimal(current_price)
    buy_price = float_to_decimal(buy_price)

    rebuy_price =
      D.sub(
        buy_price,
        D.mult(buy_price, float_to_decimal(rebuy_interval))
      )

    D.cmp(current_price, rebuy_price) == :lt
  end

  defp calculate_buy_price(price, buy_down_interval, tick_size) do
    current_price = float_to_decimal(price)
    interval = float_to_decimal(buy_down_interval)
    tick = float_to_decimal(tick_size)
    exact_buy_price = D.sub(current_price, D.mult(current_price, interval))

    exact_buy_price
    |> D.div_int(tick)
    |> D.mult(tick)
    |> D.to_float()
  end

  defp calculate_quantity(budget, price, step_size) do
    step = float_to_decimal(step_size)
    price = float_to_decimal(price)

    exact_target_quantity = D.div(budget, price)

    exact_target_quantity
    |> D.div_int(step)
    |> D.mult(step)
    |> D.to_float()
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

  defp float_to_decimal(float) when is_binary(float) do
    float |> String.to_float |> D.from_float()
  end

  defp float_to_decimal(float) do
    D.from_float(float)
  end
end
