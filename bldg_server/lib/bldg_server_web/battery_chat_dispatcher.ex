defmodule BldgServerWeb.BatteryChatDispatcher do
  use GenServer
  require Logger
  alias BldgServer.PubSub

  alias BldgServer.Batteries
  alias BldgServer.Batteries.Battery
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
    flr_url = new_message["say_flr_url"]
    IO.puts("~~~~~~~~~~~ [battery chat dispatcher] chat message received at #{flr_url}:")
    IO.inspect(new_message)

    # find battery bldgs on this floor
    battery_bldgs = Buildings.get_batteries_in_floor(flr_url)

    # Attached batteries are bound to one specific battery bldg (e.g. a per-sprite
    # file-system-battery). Route the message straight to that battery's own
    # callback_url rather than the shared, type-keyed registered pool. Collect the
    # bldg_urls handled this way so they're excluded from the registered fallback.
    attached_bldg_urls =
      Enum.reduce(battery_bldgs, MapSet.new(), fn bldg, acc ->
        case Batteries.get_attached_battery_by_bldg_url(bldg.bldg_url) do
          %Battery{callback_url: callback_url} when is_binary(callback_url) ->
            IO.puts(
              "~~~ [battery chat dispatcher] routing to attached battery at #{bldg.bldg_url} -> #{callback_url}"
            )

            send_message_to_battery(callback_url, new_message)
            MapSet.put(acc, bldg.bldg_url)

          _ ->
            acc
        end
      end)

    # Remaining (non-attached) battery bldgs keep the legacy behavior: dedup by
    # battery_type, then dispatch to a random registered callback_url for the type.
    battery_bldgs
    |> Enum.reject(fn bldg -> MapSet.member?(attached_bldg_urls, bldg.bldg_url) end)
    |> Enum.map(fn b -> Buildings.extract_battery_type(b) end)
    |> Enum.uniq()
    |> Enum.each(fn battery_type ->
      case Batteries.get_registered_callbacks(battery_type) do
        {:ok, [_ | _] = callback_urls} ->
          callback_urls |> Enum.random() |> send_message_to_battery(new_message)

        {:ok, []} ->
          IO.puts("~~~ [battery chat dispatcher] no callbacks registered for #{battery_type}")

        {:error, reason} ->
          IO.puts(
            "~~~ [battery chat dispatcher] failed to get callbacks for #{battery_type}: #{inspect(reason)}"
          )
      end
    end)

    {:noreply, state}
  end
end
