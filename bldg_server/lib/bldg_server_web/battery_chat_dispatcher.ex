defmodule BldgServerWeb.BatteryChatDispatcher do
  use GenServer
  require Logger
  alias BldgServer.PubSub

  alias BldgServer.Batteries
  alias BldgServer.Buildings

  def start_link(_) do
    GenServer.start_link(__MODULE__, name: __MODULE__)
  end

  def init(_) do
    Phoenix.PubSub.subscribe(PubSub, "chat")
    IO.puts("~~~~~~~~~~~ [battery chat dispatcher] subscribed to chat")
    {:ok, %{}}
  end

  def handle_call(:get, _, state) do
    {:reply, state, state}
  end

  def send_message_to_battery(callback_url, msg) do
    {_, msg_json} = Jason.encode(msg)
    IO.puts("~~~~~ About to invoke battery callback URL at: #{callback_url}")
    IO.inspect(msg_json)
    header_key = "content-type"
    header_val = "application/json"

    Finch.build(:post, callback_url, [{header_key, header_val}], msg_json)
    |> Finch.request(FinchClient)
    |> IO.inspect()
  end

  # def handle_info({sender, message, flr}, state) do
  def handle_info(%{event: "new_message", payload: new_message}, state) do
    # Logger.info("chat message received at #{flr} from #{sender}: #{message}")
    flr = new_message["say_flr"]
    IO.puts("~~~~~~~~~~~ [battery chat dispatcher] chat message received at #{flr}:")
    IO.inspect(new_message)

    # find battery bldgs on this floor, extract their types,
    # then look up registered callback_urls from Redis for each type
    flr
    |> Buildings.get_batteries_in_floor()
    |> Enum.map(fn b -> Buildings.extract_battery_type(b) end)
    |> Enum.uniq()
    |> Enum.each(fn battery_type ->
      case Batteries.get_registered_callbacks(battery_type) do
        {:ok, [_ | _] = callback_urls} ->
          callback_urls |> Enum.random() |> send_message_to_battery(new_message)

        {:ok, []} ->
          IO.puts("~~~ [battery chat dispatcher] no callbacks registered for #{battery_type}")

        {:error, reason} ->
          IO.puts("~~~ [battery chat dispatcher] failed to get callbacks for #{battery_type}: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end
end
