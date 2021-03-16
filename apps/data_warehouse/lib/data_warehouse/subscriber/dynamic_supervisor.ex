defmodule DataWarehouse.Subscriber.DynamicSupervisor do
  use DynamicSupervisor

  require Logger

  alias DataWarehouse.Subscriber.Worker
  alias DataWarehouse.SubscriberSettings

  @registry :subscriber_workers

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def autostart_workers do
    topics = SubscriberSettings.started_topics()

    Enum.map(topics, &start_child/1)
  end

  defp start_child(args) do
    DynamicSupervisor.start_child(__MODULE__, {Worker, args})
  end

  def start_worker(topic) do
    Logger.info("Starting storing data from #{topic} topic")

    SubscriberSettings.start(topic)

    start_child(topic)
  end

  def stop_worker(topic) do
    Logger.info("Stopping storing data from #{topic} topic")

    SubscriberSettings.stop(topic)

    stop_child(topic)
  end

  defp stop_child(args) do
    case Registry.lookup(@registry, args) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      _ -> Logger.warn("Unable to locate process assigned to #{inspect(args)}")
    end
  end
end
