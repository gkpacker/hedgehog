defmodule Naive do

  alias Naive.{DynamicSymbolSupervisor, Repo, Schema}

  defdelegate start_trading(symbol), to: DynamicSymbolSupervisor, as: :start_worker
  defdelegate stop_trading(symbol), to: DynamicSymbolSupervisor, as: :stop_worker
  defdelegate shutdown_trading(symbol), to: DynamicSymbolSupervisor, as: :shutdown_worker

  def update_all_settings do
    settings = Application.get_env(:naive, :trading).defaults

    Repo.update_all(Schema.Settings, set: Map.to_list(settings))
  end
end
