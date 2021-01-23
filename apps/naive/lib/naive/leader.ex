defmodule Naive.Leader do
  use GenServer

  alias Decimal, as: D
  alias Naive.Trader

  require Logger

  @binance_client Application.get_env(:naive, :binance_client)

  defmodule State do
    defstruct symbol: nil,
              settings: nil,
              traders: []
  end

  defmodule TraderData do
    defstruct pid: nil, ref: nil, state: nil
  end

  def start_link(symbol) do
    GenServer.start_link(
      __MODULE__,
      symbol,
      name: :"#{__MODULE__}-#{symbol}"
    )
  end

  def init(symbol) do
    {
      :ok,
      %State{symbol: symbol},
      {:continue, :start_traders}
    }
  end

  def notify(:trader_state_updated, trader_state) do
    GenServer.call(
      :"#{__MODULE__}-#{trader_state.symbol}",
      {:update_trader_state, trader_state}
    )
  end

  def notify(:rebuy_triggered, trader_state) do
    GenServer.call(
      :"#{__MODULE__}-#{trader_state.symbol}",
      {:rebuy_triggered, trader_state}
    )
  end

  def handle_continue(:start_traders, %{symbol: symbol} = state) do
    settings = fetch_symbol_settings(symbol)
    trader_state = fresh_trader_state(symbol, settings)
    traders = [start_new_trader(trader_state)]

    {:noreply, %{state | settings: settings, traders: traders}}
  end

  def handle_call(
        {:update_trader_state, new_trader_state},
        {trader_pid, _},
        %{traders: traders} = state
      ) do
    case Enum.find_index(traders, &(&1.pid == trader_pid)) do
      nil ->
        Logger.warn("Tried to update the state of trader that leader is not aware of")

        {:reply, :ok, state}

      index ->
        old_trader_data = Enum.at(traders, index)
        new_trader_data = %{old_trader_data | state: new_trader_state}

        {:reply, :ok, %{state | traders: List.replace_at(traders, index, new_trader_data)}}
    end
  end

  def handle_call(
        {:rebuy_triggered, new_trader_state},
        {trader_pid, _},
        %{traders: traders, symbol: symbol, settings: settings} = state
      ) do
    case Enum.find_index(traders, &(&1.pid == trader_pid)) do
      nil ->
        Logger.warn("Rebuy triggered by trader that leader is not aware of")
        {:reply, :ok, state}

      index ->
        traders =
          if settings.chunks == length(traders) do
            Logger.info("All traders already started for #{symbol}")
            traders
          else
            Logger.info("Starting new trader for #{symbol}")

            new_trader =
              symbol
              |> fresh_trader_state(settings)
              |> start_new_trader

            [new_trader | traders]
          end

        old_trader_data = Enum.at(traders, index)
        new_trader_data = %{old_trader_data | state: new_trader_state}

        {:reply, :ok, %{state | traders: List.replace_at(traders, index, new_trader_data)}}
    end
  end

  def handle_info(
        {:DOWN, _ref, :process, trader_pid, :normal},
        %{traders: traders} = state
      ) do
    Logger.info("Trader finished - restarting")

    case Enum.find_index(traders, &(&1.pid == trader_pid)) do
      nil ->
        Logger.warn("Tried to remove finished trader that leader is not aware of")
        {:noreply, state}

      index ->
        trader_data = Enum.at(traders, index)
        new_trader_data = start_new_trader(%{trader_data.state | buy_order: nil, sell_order: nil})
        new_traders = List.replace_at(traders, index, new_trader_data)
        {:noreply, %{state | traders: new_traders}}
    end
  end

  def handle_info(
        {:DOWN, _ref, :process, trader_pid, _reason},
        %{traders: traders} = state
      ) do
    Logger.error("Trader died - trying to restart")

    case Enum.find_index(traders, &(&1.pid == trader_pid)) do
      nil ->
        Logger.warn("Tried to restart trader but failed to find its cached state")
        {:noreply, state}

      index ->
        trader_data = Enum.at(traders, index)
        new_trader_data = start_new_trader(trader_data.state)
        new_traders = List.replace_at(traders, index, new_trader_data)
        {:noreply, %{state | traders: new_traders}}
    end
  end

  defp fresh_trader_state(symbol, settings) do
    budget_by_trader =
      settings.budget
      |> D.new()
      |> D.div(D.new(settings.chunks))

    %Trader.State{
      id: System.system_time(),
      symbol: symbol,
      budget: budget_by_trader,
      buy_down_interval: settings.buy_down_interval,
      profit_interval: settings.profit_interval,
      rebuy_interval: settings.rebuy_interval,
      rebuy_notified: settings.rebuy_notified,
      tick_size: settings.tick_size,
      step_size: settings.step_size
    }
  end

  defp start_new_trader(state) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        :"Naive.DynamicTraderSupervisor-#{state.symbol}",
        {Naive.Trader, state}
      )

    ref = Process.monitor(pid)

    %TraderData{pid: pid, ref: ref, state: state}
  end

  defp fetch_symbol_settings(symbol) do
    symbol_filters = fetch_symbol_filters(symbol)

    Map.merge(
      %{
        chunks: 4,
        budget: 20,
        # 0.5%
        buy_down_interval: 0.005,
        # -0.12% for quick testing
        profit_interval: -0.0012,
        # 0.5%
        rebuy_interval: 0.005,
        rebuy_notified: false
      },
      symbol_filters
    )
  end

  defp fetch_symbol_filters(symbol) do
    symbol_filters =
      @binance_client.get_exchange_info()
      |> elem(1)
      |> Map.get(:symbols)
      |> Enum.find(&(&1["symbol"] == symbol))
      |> Map.get("filters")

    tick_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))
      |> Map.get("tickSize")

    step_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "LOT_SIZE"))
      |> Map.get("stepSize")

    %{
      tick_size: tick_size,
      step_size: step_size
    }
  end
end