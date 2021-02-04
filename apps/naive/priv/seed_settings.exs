require Logger

alias Decimal, as: D
alias Naive.Repo
alias Naive.Schema.Settings

binance_client = Application.get_env(:naive, :binance_client)

Logger.info("Fetching exchange info from Binance to create trading settings")

{:ok, %{symbols: symbols}} = binance_client.get_exchange_info()

Logger.info("Inserting default settings for symbols")

%{
  chunks: chunks,
  budget: budget,
  buy_down_interval: buy_down_interval,
  profit_interval: profit_interval,
  rebuy_interval: rebuy_interval
} = Application.get_env(:naive, :trading).defaults

timestamp = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

base_settings = %{
  symbol: "",
  status: "off",
  inserted_at: timestamp,
  updated_at: timestamp,
  chunks: chunks,
  budget: D.from_float(budget),
  buy_down_interval: D.from_float(buy_down_interval),
  profit_interval: D.from_float(profit_interval),
  rebuy_interval: D.from_float(rebuy_interval)
}

maps = Enum.map(symbols, &(%{base_settings | symbol: &1["symbol"]}))

{count, nil} = Repo.insert_all(Settings, maps)

Logger.info("Inserted settings for #{count} symbols")
