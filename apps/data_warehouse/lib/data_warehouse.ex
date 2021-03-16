defmodule DataWarehouse do
  import Ecto.Query

  alias DataWarehouse.Subscriber.DynamicSupervisor

  def start_storing(stream, symbol) do
    stream
    |> build_topic(symbol)
    |> DynamicSupervisor.start_worker()
  end

  def stop_storing(stream, symbol) do
    stream
    |> build_topic(symbol)
    |> DynamicSupervisor.stop_worker()
  end

  defp build_topic(stream, symbol) do
    "#{String.downcase(stream)}:#{String.upcase(symbol)}"
  end

  # TODO: move to a calculation dedicated module
  def estimate_profits_since_minutes_ago(symbol, minutes_ago) do
    seconds_ago = -minutes_ago * 60
    from_date = NaiveDateTime.add(NaiveDateTime.utc_now(), seconds_ago)
    symbol = String.upcase(symbol)

    orders =
      o in DataWarehouse.Order
      |> from(
        where: o.inserted_at >= ^from_date and o.symbol == ^symbol
      )
      |> DataWarehouse.Repo.all()

    total_sold = sum_orders(orders, "SELL")
    total_bought = sum_orders(orders, "BUY")

    total_sold - total_bought
  end

  defp sum_orders(orders, type) do
    orders
    |> Enum.filter(&(&1.side == type))
    |> Enum.reduce(0.0, &sum_total/2)
  end

  defp sum_total(%{original_quantity: quantity, price: price}, total) do
    total + String.to_float(quantity) * String.to_float(price)
  end
end
