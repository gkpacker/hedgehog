defmodule DataWarehouse.SubscriberSettings do
  alias DataWarehouse.{Repo, Schema}

  import Ecto.Query, only: [from: 2]

  def started_topics do
    (s in Schema.SubscriberSettings)
    |> from(where: s.status == "on", select: s.topic)
    |> Repo.all()
  end

  def stop(topic), do: update_status(topic, "off")
  def start(topic), do: update_status(topic, "on")

  defp update_status(topic, status) when is_binary(topic) and is_binary(status) do
    Repo.insert(
      %Schema.SubscriberSettings{
        topic: topic,
        status: status
      },
      on_conflict: :replace_all,
      conflict_target: :topic
    )
  end
end
