defmodule DataWarehouse.Publisher do
  # DataWarehouse.Publisher.start_link(%{  type: :trade_events,  symbol: "XRPUSDT",  from: "2019-06-02",  to: "2019-06-04",  interval: 5})
  use Task

  import Ecto.Query, only: [from: 2]

  require Logger

  alias DataWarehouse.Repo

  def start_link(%{} = options) do
    Task.start_link(
      __MODULE__,
      :run,
      [options]
    )
  end

  def run(%{
        type: :trade_events,
        symbol: symbol,
        from: from,
        to: to,
        interval: interval
      }) do
    from_ts = convert_to_ms("#{from}T00:00:00.000Z")
    to_ts = convert_to_ms("#{to}T00:00:00.000Z")

    Logger.info("DataWarehouse.Publisher is broadcasting to #{symbol}")

    Repo.transaction(
      fn ->
        (te in DataWarehouse.TradeEvent)
        |> from(
          where:
            te.symbol == ^symbol and
              te.trade_time >= ^from_ts and
              te.trade_time < ^to_ts,
          order_by: te.trade_time
        )
        |> Repo.stream()
        |> Enum.with_index()
        |> Enum.map(fn {row, index} ->
          :timer.sleep(interval)

          if rem(index, 10_000) == 0 do
            Logger.info("Publisher broadcasted #{index} events")
          end

          publish_trade_event(row)
        end)
      end,
      timeout: :infinity
    )

    Logger.info("Publisher finished streaming trade events")
  end

  defp publish_trade_event(%DataWarehouse.TradeEvent{} = trade_event) do
    new_trade_event =
      struct(
        Streamer.Binance.TradeEvent,
        Map.to_list(trade_event)
      )

    symbol = String.downcase(trade_event.symbol)

    Logger.debug(
      "Trade event published " <>
        "#{trade_event.symbol}@#{trade_event.price}"
    )

    Phoenix.PubSub.broadcast(
      Streamer.PubSub,
      "trade_events:#{symbol}",
      new_trade_event
    )
  end

  defp convert_to_ms(iso8601_date_string) do
    iso8601_date_string
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
    |> Kernel.*(1000)
  end
end
