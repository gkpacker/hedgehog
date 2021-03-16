defmodule Streamer.Supervisor do
  use Supervisor, restart: :temporary

  def start_link(_) do
    Supervisor.start_link(
      __MODULE__,
      [],
      name: __MODULE__
    )
  end

  def init(_) do
    Supervisor.init(
      [
        {Phoenix.PubSub, name: Streamer.PubSub, adapter_name: Phoenix.PubSub.PG2},
        {Streamer.DynamicStreamerSupervisor, []},
        {Task,
         fn ->
           Streamer.DynamicStreamerSupervisor.autostart_workers()
         end}
      ],
      strategy: :rest_for_one
    )
  end
end
