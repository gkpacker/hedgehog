# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :streamer,
  ecto_repos: [Streamer.Repo]

config :streamer, Streamer.Repo,
  database: "streamer",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :naive, Naive.Repo,
  database: "naive",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :data_warehouse,
  ecto_repos: [DataWarehouse.Repo]

config :data_warehouse, DataWarehouse.Repo,
  database: "data_warehouse",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :logger,
  level: :info

config :naive,
  binance_client: BinanceMock,
  ecto_repos: [Naive.Repo],
  trading: %{
    defaults: %{
      chunks: 2,
      budget: 20_000.0, # 200 dolares
      buy_down_interval: 0.0005,
      profit_interval:  0.0012,
      rebuy_interval: 0.005
    }
  }


config :binance,
  api_key: "",
  secret_key: "",
  end_point: "https://api.binance.us"
