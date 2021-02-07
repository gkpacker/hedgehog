defmodule Naive.SymbolSupervisor do
  use Supervisor, restart: :temporary

  def start_link(symbol) do
    Supervisor.start_link(
      __MODULE__,
      symbol,
      name: :"#{__MODULE__}-#{symbol}"
    )
  end

  def init(symbol) do
    Supervisor.init(
      [
        {
          DynamicSupervisor,
          strategy: :one_for_one, name: :"Naive.DynamicTraderSupervisor-#{symbol}"
        },
        {Naive.Leader, symbol}
      ],
      strategy: :one_for_all
    )
  end
end
