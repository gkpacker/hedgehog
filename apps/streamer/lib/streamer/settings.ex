defmodule Streamer.Settings do
  alias Streamer.{Repo, Schema}

  import Ecto.Query, only: [from: 2]

  def started_symbols do
    (s in Schema.Settings)
    |> from(where: s.status == "on", select: s.symbol)
    |> Repo.all()
  end

  def stop(symbol), do: update_status(symbol, "off")
  def start(symbol), do: update_status(symbol, "on")
  def shutdown(symbol), do: update_status(symbol, "shutdown")

  defp update_status(symbol, status) do
    Schema.Settings
    |> Repo.get_by(symbol: symbol)
    |> Ecto.Changeset.change(%{status: status})
    |> Repo.update()
  end
end
