defmodule Naive do
  def start_trading(symbol) do
    Naive.Server.start_trading(symbol)
  end
end
