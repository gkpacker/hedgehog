defmodule Streamer do
  @moduledoc false

  alias Streamer.DynamicStreamerSupervisor

  defdelegate start_streaming(symbol), to: DynamicStreamerSupervisor, as: :start_worker
  defdelegate stop_streaming(symbol), to: DynamicStreamerSupervisor, as: :stop_worker
end
