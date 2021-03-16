defmodule DataWarehouse.Subscriber.Worker do
  use GenServer

  require Logger

  def start_link(topic) do
    GenServer.start_link(
      __MODULE__,
      topic,
      name: via_tuple(topic)
    )
  end

  defp via_tuple(topic) do
    {:via, Registry, {:subscriber_workers, topic}}
  end

  def init(topic) do
    Logger.info("DataWarehouse worker is subscribing to #{topic}")

    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      topic
    )

    {:ok, topic}
  end

  def handle_info(
        %Streamer.Binance.TradeEvent{} = trade_event,
        topic
      ) do
    opts =
      trade_event
      |> Map.to_list()
      |> Keyword.delete(:__struct__)

    DataWarehouse.Schema.TradeEvent
    |> struct!(opts)
    |> DataWarehouse.Repo.insert!()

    {:noreply, topic}
  end

  def handle_info(%Binance.Order{} = order, topic) do
    converted_order = %DataWarehouse.Schema.Order{
      symbol: order.symbol,
      order_id: order.order_id,
      client_order_id: order.client_order_id,
      price: order.price,
      original_quantity: order.orig_qty,
      executed_quantity: order.executed_qty,
      cummulative_quote_quantity: "0.00000000",
      status: order.status,
      time_in_force: order.time_in_force,
      type: order.type,
      side: order.side,
      stop_price: "0.00000000",
      iceberg_quantity: "0.00000000",
      time: order.time,
      update_time: order.update_time
    }

    DataWarehouse.Repo.insert(
      converted_order,
      on_conflict: :replace_all,
      conflict_target: :order_id
    )

    {:noreply, topic}
  end
end
