defmodule Naive.MixProject do
  use Mix.Project

  def project do
    [
      app: :naive,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      application: [:binance, :phoenix_pubsub],
      extra_applications: [:logger],
      # applications: [:binance],
      mod: {Naive.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:binance, "~> 0.7.1"},
      {:binance_mock, in_umbrella: true},
      {:decimal, "~> 1.0"},
      {:ecto_sql, "~> 3.5.4"},
      {:ecto_enum, "~> 1.4"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:binance_mock, in_umbrella: true},
      {:streamer, in_umbrella: true}
    ]
  end
end
