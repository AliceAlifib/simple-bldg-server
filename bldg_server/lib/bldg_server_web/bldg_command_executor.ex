defmodule BldgServerWeb.BldgCommandExecutor do
  use GenServer
  require Logger
  alias Jason
  alias BldgServer.PubSub
  alias BldgServer.Buildings
  alias BldgServer.Relations

  def start_link(_) do
    GenServer.start_link(__MODULE__, name: __MODULE__)
  end

  def init(_) do
    Phoenix.PubSub.subscribe(PubSub, "chat")
    IO.puts("~~~~~~~~~~~~ [bldg command executor] subscribed to chat")
    {:ok, %{}}
  end

  def handle_call(:get, _, state) do
    {:reply, state, state}
  end

  def parse_command(msg_text) do
    String.split(msg_text, " ")
  end

  def determine_wallpaper_based_on_location(x, _y) do
    # TODO generalize a bit
    cond do
      x > 80 -> 1
      x <= 80 and x > 66 -> 2
      x <= 66 and x > 18 -> 3
      x <= 18 and x > -28 -> 4
      x <= -28 -> 5
    end
  end

  def execute_command(["/add", "owner", email, "to", "bldg", name], msg) do
    flr_url = msg["say_flr_url"]
    bldg_url = "#{flr_url}#{Buildings.address_delimiter()}#{name}"
    bldg = Buildings.get_by_bldg_url(bldg_url)
    # verify that the speaker is an owner (directly or via ancestor)
    if not Buildings.is_authorized_owner?(msg["resident_email"], bldg) do
      raise "Unauthorized"
    else
      Buildings.update_bldg(bldg, %{"owners" => [email | bldg.owners]})
      IO.puts("owner added to bldg #{bldg_url}: #{email}")
    end
  end

  def execute_command(["/remove", "owner", email, "from", "bldg", name], msg) do
    flr_url = msg["say_flr_url"]
    bldg_url = "#{flr_url}#{Buildings.address_delimiter()}#{name}"
    bldg = Buildings.get_by_bldg_url(bldg_url)
    # verify that the speaker is an owner (directly or via ancestor)
    if not Buildings.is_authorized_owner?(msg["resident_email"], bldg) do
      raise "Unauthorized"
    else
      pos = Enum.find_index(bldg.owners, fn x -> x == email end)

      if pos == nil do
        raise "tried to remove non-existing owner #{email} from #{bldg_url}"
      else
        new_owners = List.delete_at(bldg.owners, pos)
        Buildings.update_bldg(bldg, %{"owners" => new_owners})
        IO.puts("owner removed from bldg #{bldg_url}: #{email}")
      end
    end
  end

  # create road between 2 bldgs (using their websites)
  # TODO handle the case where there are multiple bldgs for the same website - check the ones owned by the user in order to resolve
  def execute_command(["/connect", "between", name1, "and", name2 | rest], msg) do
    # create a road between the given bldgs, inside the given flr.
    # Optional tail: `with color <name> and class <highway|road|lane|path>`
    # (either order; either one alone also valid). Defaults: color=nil,
    # class="road" — bare `/connect between A and B` renders unchanged.

    {color, road_class} = parse_connect_options(rest)

    # validate that the actor resident/bldg has the sufficient permissions
    container_bldg = Buildings.get_flr_bldg(msg["say_flr"]) |> Buildings.get_bldg!()

    if not Buildings.is_authorized_owner?(msg["resident_email"], container_bldg) do
      raise "#{msg["resident_email"]} is not authorized to create roads inside #{container_bldg.web_url}"
    else
      # TODO return proper errors
      flr_url = msg["say_flr_url"]
      bldg1 = Buildings.get_by_bldg_url("#{flr_url}#{Buildings.address_delimiter()}#{name1}")
      bldg2 = Buildings.get_by_bldg_url("#{flr_url}#{Buildings.address_delimiter()}#{name2}")

      cond do
        is_nil(bldg1) or is_nil(bldg2) ->
          # A road endpoint isn't on this floor: a race-late create (the bldg's
          # relocate echo hasn't landed) or a stale re-emit (the bldg moved or was
          # removed by a later render). Skip gracefully instead of crashing on
          # nil.address — that raised an Internal Server Error (HTTP 500) for what
          # is a benign, self-correcting condition: batteries re-emit roads
          # idempotently, so a transient miss heals on a later pass.
          IO.puts("~~ /connect skipped: endpoint not found on #{flr_url} (#{name1} and/or #{name2})")
          {:ok, :skipped}

        true ->
          from_addr = bldg1.address
          {from_x, from_y} = Buildings.extract_coords(from_addr)
          to_addr = bldg2.address
          {to_x, to_y} = Buildings.extract_coords(to_addr)

          road = %{
            "flr" => msg["say_flr"],
            "flr_url" => msg["say_flr_url"],
            "from_address" => from_addr,
            "to_address" => to_addr,
            "from_x" => from_x,
            "from_y" => from_y,
            "to_x" => to_x,
            "to_y" => to_y,
            "owners" => [msg["resident_email"]],
            "color" => color,
            "road_class" => road_class || "road"
          }

          # Idempotent: re-emitting an identical road (watch / re-render passes, or
          # the organize-check's road re-emission) must not stack duplicate records.
          case Relations.find_road(msg["say_flr"], from_addr, to_addr) do
            nil -> Relations.create_road(road)
            existing -> {:ok, existing}
          end
      end
    end
  end

  # Parse the optional `with color X and class Y` (or `with class Y and color X`)
  # tail of a `/connect between A and B` command. Returns {color, class} where
  # either may be nil if not specified.
  defp parse_connect_options([]), do: {nil, nil}
  defp parse_connect_options(["with" | rest]), do: parse_connect_kwargs(rest, nil, nil)
  defp parse_connect_options(_), do: {nil, nil}

  defp parse_connect_kwargs([], color, klass), do: {color, klass}

  defp parse_connect_kwargs(["color", v | rest], _color, klass),
    do: parse_connect_kwargs(skip_and(rest), v, klass)

  defp parse_connect_kwargs(["class", v | rest], color, _klass),
    do: parse_connect_kwargs(skip_and(rest), color, v)

  defp parse_connect_kwargs([_ | rest], color, klass),
    do: parse_connect_kwargs(rest, color, klass)

  defp skip_and(["and" | rest]), do: rest
  defp skip_and(rest), do: rest

  def fetch_data(data_url) do
    case data_url do
      "" ->
        ""

      _ ->
        # Check if data_url starts with redis:// or http://
        protocol =
          cond do
            String.starts_with?(data_url, "redis://") -> :redis
            String.starts_with?(data_url, "http://") -> :http
            String.starts_with?(data_url, "https://") -> :http
            true -> :unknown
          end

        if protocol == :unknown do
          raise "Unknown protocol in data_url: #{data_url}"
        end

        if protocol == :http do
          raise "HTTP protocol is not implemented yet for data_url (#{data_url})"
        end

        # protocol is :redis
        redis_key = String.replace_prefix(data_url, "redis://", "")

        case Redix.command(:redix, ["GET", redis_key]) do
          {:ok, data} ->
            Logger.info("Successfully read data from redis_key #{redis_key}: (#{data})")
            data

          {:error, %Redix.ConnectionError{reason: error_reason}} ->
            # Surface the failure instead of returning the error reason *as data*
            # (which silently persisted e.g. `:closed` as the bldg's content).
            Logger.error("Failed to read data from Redis: #{error_reason}")
            raise "Failed to read data from Redis (#{redis_key}): #{error_reason}"
        end
    end
  end

  def create_bldg_from_command(
        entity_type,
        name,
        web_url,
        summary,
        category,
        picture_url,
        data_url,
        state,
        color,
        size,
        variant,
        width,
        height,
        msg
      ) do
    # create a bldg with the given entity-type & name, inside the given flr & bldg

    # validate that the actor resident/bldg has the sufficient permissions
    container_bldg = Buildings.get_flr_bldg(msg["say_flr_url"]) |> Buildings.get_by_bldg_url()

    if not Buildings.is_authorized_owner?(msg["resident_email"], container_bldg) do
      raise "#{msg["resident_email"]} is not authorized to create bldgs inside #{container_bldg.web_url}"
    else
      # TODO if creating under a given bldg, send its container_web_url instead of flr

      data = fetch_data(data_url)

      # if given location, use it, otherwise default to 0,0
      {x, y} =
        case Map.get(msg, "say_location") do
          nil -> {0, 0}
          say_loc -> Buildings.extract_coords(say_loc) |> Buildings.move_from_speaker(-4)
        end

      # Always derive flr from the authoritative container_bldg.address (looked up via
      # bldg_url above). A client-supplied say_flr can carry stale coord tuples that don't
      # match the parent's real address, which strands the child as an orphan.
      flr = "#{container_bldg.address}/l#{Buildings.extract_flr_level(msg["say_flr_url"])}"

      updated_location = "#{flr}#{Buildings.address_delimiter()}b(#{x},#{y})"

      entity =
        %{
          "flr" => flr,
          "flr_url" => msg["say_flr_url"],
          "address" => updated_location,
          "x" => x,
          "y" => y,
          "name" => name,
          "entity_type" => entity_type,
          "web_url" => web_url,
          "summary" => summary,
          "category" => category,
          "picture_url" => picture_url,
          "data" => data,
          "state" => state,
          "owners" => [msg["resident_email"]]
        }
        |> put_if_present("color", color)
        |> put_if_present("size", size)
        |> put_if_present("variant", variant)
        |> put_if_present("width", width)
        |> put_if_present("height", height)

      Buildings.build(entity)
      |> Buildings.create_bldg(msg)
    end
  end

  # Only set the field when the chat command actually supplied a value.
  # The parser uses "" as the unset sentinel; passing "" through would fail
  # validate_inclusion on :size and pollute the field needlessly.
  defp put_if_present(map, _key, ""), do: map
  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  def execute_command(["/create", entity_type, "bldg", "with" | parameters_tokens], msg) do
    # Initialize variables
    name = ""
    web_url = ""
    summary = ""
    category = ""
    picture_url = ""
    data_url = ""
    state = ""
    color = ""
    size = ""
    variant = ""
    # nil (not "") sentinel: dimensions are integers, so put_if_present skips
    # them when unspecified and the schema default (1) applies.
    width = nil
    height = nil

    # Loop through parameters with index
    Enum.with_index(parameters_tokens)
    |> Enum.reduce(
      {name, web_url, summary, category, picture_url, data_url, state, color, size, variant, width,
       height},
      fn
        {"name", i}, acc ->
          name = Enum.at(parameters_tokens, i + 1)
          acc = put_elem(acc, 0, name)
          acc

        {"web_url", i}, acc ->
          web_url = Enum.at(parameters_tokens, i + 1)
          acc = put_elem(acc, 1, web_url)
          acc

        {"summary", i}, acc ->
          # Get all tokens after summary until next parameter or end
          summary_tokens =
            parameters_tokens
            |> Enum.drop(i + 1)
            |> Enum.take_while(fn x ->
              not Enum.member?(
                [
                  "name",
                  "web_url",
                  "category",
                  "picture_url",
                  "data_url",
                  "state",
                  "color",
                  "size",
                  "variant",
                  "width",
                  "height"
                ],
                x
              )
            end)

          summary = Enum.join(summary_tokens, " ")
          acc = put_elem(acc, 2, summary)
          acc

        {"category", i}, acc ->
          category = Enum.at(parameters_tokens, i + 1)
          acc = put_elem(acc, 3, category)
          acc

        {"picture_url", i}, acc ->
          picture_url = Enum.at(parameters_tokens, i + 1)
          acc = put_elem(acc, 4, picture_url)
          acc

        {"data_url", i}, acc ->
          data_url = Enum.at(parameters_tokens, i + 1)
          acc = put_elem(acc, 5, data_url)
          acc

        {"state", i}, acc ->
          state = Enum.at(parameters_tokens, i + 1)
          acc = put_elem(acc, 6, state)
          acc

        {"color", i}, acc ->
          color = Enum.at(parameters_tokens, i + 1)
          acc = put_elem(acc, 7, color)
          acc

        {"size", i}, acc ->
          size = Enum.at(parameters_tokens, i + 1)
          acc = put_elem(acc, 8, size)
          acc

        {"variant", i}, acc ->
          variant = Enum.at(parameters_tokens, i + 1)
          acc = put_elem(acc, 9, variant)
          acc

        {"width", i}, acc ->
          put_elem(acc, 10, parse_dimension(Enum.at(parameters_tokens, i + 1)))

        {"height", i}, acc ->
          put_elem(acc, 11, parse_dimension(Enum.at(parameters_tokens, i + 1)))

        _, acc ->
          acc
      end
    )
    |> then(fn {name, web_url, summary, category, picture_url, data_url, state, color, size,
                variant, width, height} ->
      create_bldg_from_command(
        entity_type,
        name,
        web_url,
        summary,
        category,
        picture_url,
        data_url,
        state,
        color,
        size,
        variant,
        width,
        height,
        msg
      )
    end)
  end

  # Dimensions must be whole positive cell-counts; a missing or non-integer token
  # yields nil so the schema default (1) applies rather than a bad value.
  defp parse_dimension(nil), do: nil

  defp parse_dimension(token) do
    case Integer.parse(token) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  # move bldg
  def execute_command(
        ["/move", "bldg", name, "here"],
        %{say_location: say_location, say_flr_url: say_flr_url, resident_email: resident_email} =
          msg
      ) do
    # update the location of the bldg with the given name to the say location
    # TODO composite bldgs should update the location of their children bldgs as well
    {x, y} = Buildings.extract_coords(say_location)
    flr_url = say_flr_url
    bldg_url = "#{flr_url}#{Buildings.address_delimiter()}#{name}"
    bldg = Buildings.get_by_bldg_url(bldg_url)
    # verify that the speaker is an owner (directly or via ancestor)
    if not Buildings.is_authorized_owner?(resident_email, bldg) do
      raise "Unauthorized"
    else
      Buildings.update_bldg(bldg, %{"address" => say_location, "x" => x, "y" => y})
    end
  end

  # move bldg - missing parameters
  def execute_command(
        ["/move", "bldg", _name, "here"],
        msg
      ) do
    received_keys = msg |> Map.keys() |> Enum.join(", ")

    raise "Missing required say fields (say_location, say_flr_url, resident_email)- received only: #{received_keys}"
  end

  # relocate bldg
  def execute_command(
        ["/relocate", "bldg", bldg_url, "here"],
        %{
          "say_location" => say_location,
          "say_flr" => say_flr,
          "say_flr_url" => say_flr_url,
          "resident_email" => resident_email
        } =
          msg
      ) do
    # update the bldg_url & address of the bldg with the given bldg_url to the say location
    # TODO composite bldgs should update the location of their children bldgs as well
    # TODO handle location collisions
    {x, y} = Buildings.extract_coords(say_location)
    name = Buildings.extract_name(bldg_url)
    flr_url = say_flr_url
    new_bldg_url = "#{flr_url}#{Buildings.address_delimiter()}#{name}"
    bldg = Buildings.get_by_bldg_url(bldg_url)
    container_bldg_url = Buildings.get_container(flr_url)
    container_bldg = Buildings.get_by_bldg_url(container_bldg_url)

    case {bldg, container_bldg} do
      {nil, _} ->
        IO.puts("Bldg given to relocate couldn't be found: #{bldg_url}")

      {_, nil} ->
        IO.puts("Container of bldg given to relocate couldn't be found: #{container_bldg_url}")

      _ ->
        attrs = %{
          "bldg_url" => new_bldg_url,
          "address" => say_location,
          "x" => x,
          "y" => y,
          "flr" => say_flr,
          "flr_url" => flr_url,
          "nesting_depth" => container_bldg.nesting_depth + 1,
          "flr_level" => Buildings.extract_flr_level(say_flr)
        }

        # verify that the speaker is an owner (directly or via ancestor)
        if not Buildings.is_authorized_owner?(resident_email, bldg) do
          raise "Unauthorized"
        else
          # TODO address may not be exactly the say_location
          Buildings.update_bldg(bldg, attrs)
        end
    end
  end

  # relocate bldg - missing parameters
  def execute_command(
        ["/relocate", "bldg", _bldg_url, "here"],
        msg
      ) do
    received_keys = msg |> Map.keys() |> Enum.join(", ")

    raise "Missing required say fields (say_location, say_flr, say_flr_url, resident_email) - received only: #{received_keys}"
  end

  # promote bldg inside
  def execute_command(
        ["/promote", "bldg", name, "inside"],
        %{
          "say_location" => say_location,
          "say_flr_url" => say_flr_url
        } =
          msg
      ) do
    # get speaker location (we'll need it to determine which wallpaper to set)
    {x, y} = Buildings.extract_coords(say_location)
    # get the promoted bldg
    flr_url = say_flr_url
    bldg_url = "#{flr_url}#{Buildings.address_delimiter()}#{name}"
    bldg = Buildings.get_by_bldg_url(bldg_url)
    picture_url = bldg.picture_url

    cond do
      picture_url == nil ->
        raise "Promoted entity has no picture URL"

      true ->
        # determine nearest wallpaper
        wallpaper_num = determine_wallpaper_based_on_location(x, y)
        # get the container bldg
        container_bldg_url = Buildings.get_container(flr_url)
        container = Buildings.get_by_bldg_url(container_bldg_url)
        {_, data} = Jason.decode(container.data || "{}")

        {_, new_data} =
          Map.merge(data, %{"promoted-inside-#{wallpaper_num}-picture-url" => bldg.picture_url})
          |> Jason.encode()

        # update bldg
        Buildings.update_bldg(container, %{"data" => new_data})
    end
  end

  # promote bldg inside - missing parameters
  def execute_command(
        ["/promote", "bldg", _name, "inside"],
        msg
      ) do
    received_keys = msg |> Map.keys() |> Enum.join(", ")

    raise "Missing required say fields (say_location, say_flr_url)- received only: #{received_keys}"
  end

  # demote bldg inside
  def execute_command(
        ["/demote", "bldg", name, "inside"],
        %{
          "say_flr_url" => say_flr_url
        } =
          msg
      ) do
    # get the promoted bldg
    flr_url = say_flr_url
    bldg_url = "#{flr_url}#{Buildings.address_delimiter()}#{name}"
    bldg = Buildings.get_by_bldg_url(bldg_url)
    picture_url = bldg.picture_url

    cond do
      picture_url == nil ->
        raise "Demoted entity has no picture URL"

      true ->
        # get the container bldg
        container_bldg_url = Buildings.get_container(flr_url)
        container = Buildings.get_by_bldg_url(container_bldg_url)
        {_, data} = Jason.decode(container.data || "{}")
        # find the key matching the picture-url

        case Enum.find(data, fn {_, val} -> val == picture_url end) do
          nil ->
            # Guard the previous `nil |> elem(0)` crash when the bldg was never
            # promoted into this container (no matching picture-url key).
            raise "Cannot demote #{name}: it is not promoted inside #{container.web_url}"

          {data_key, _} ->
            {_, new_data} = Map.delete(data, data_key) |> Jason.encode()
            # update bldg
            Buildings.update_bldg(container, %{"data" => new_data})
        end
    end
  end

  # demote bldg inside - missing parameters
  def execute_command(
        ["/demote", "bldg", _name, "inside"],
        msg
      ) do
    received_keys = msg |> Map.keys() |> Enum.join(", ")
    raise "Missing required say fields (say_flr_url)- received only: #{received_keys}"
  end

  @editable_fields ~w(state summary category picture_url web_url data tags color size variant)

  def execute_command(["/edit", name, field, value_head | value_rest], msg) do
    value = Enum.join([value_head | value_rest], " ")
    flr_url = msg["say_flr_url"]
    bldg_url = "#{flr_url}#{Buildings.address_delimiter()}#{name}"
    bldg = Buildings.get_by_bldg_url(bldg_url)

    cond do
      bldg == nil ->
        raise "Bldg not found: #{bldg_url}"

      field not in @editable_fields ->
        raise "Field '#{field}' is not editable via chat. Editable fields: #{Enum.join(@editable_fields, ", ")}"

      not Buildings.is_authorized_owner?(msg["resident_email"], bldg) ->
        raise "Unauthorized"

      true ->
        Buildings.update_bldg(bldg, %{field => cast_edit_value(field, value)})
        IO.puts("bldg edited: #{bldg_url} #{field}=#{value}")
    end
  end

  def execute_command(["/edit", _name, _field], _msg) do
    raise "Missing value for /edit - usage: /edit <bldg_name> <field> <value>"
  end

  defp cast_edit_value("tags", value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp cast_edit_value(_field, value), do: value

  def execute_command(["/delete", "bldg", name], msg) do
    flr_url = msg["say_flr_url"]
    bldg_url = "#{flr_url}#{Buildings.address_delimiter()}#{name}"
    bldg = Buildings.get_by_bldg_url(bldg_url)

    if not Buildings.is_authorized_owner?(msg["resident_email"], bldg) do
      raise "Unauthorized"
    else
      Buildings.delete_bldg_cascade(bldg)
      IO.puts("bldg deleted (cascade): #{bldg_url}")
    end
  end

  def execute_command(msg_parts, _msg) do
    Logger.info("Ignoring unknown command:")
    IO.inspect(msg_parts)
  end

  # def handle_info({sender, message, flr}, state) do
  def handle_info(%{event: "new_message", payload: new_message}, state) do
    # Logger.info("chat message received at #{flr} from #{sender}: #{message}")
    Logger.info(
      "~~~~~~~~~~~~ [bldg command executor] chat message received: #{new_message["message"]}"
    )

    # Commands arrive via fire-and-forget PubSub broadcast, so a raise here
    # (Unauthorized, missing bldg, bad parse) would crash this GenServer and drop
    # its "chat" subscription until the supervisor restarts it. Isolate failures
    # to the offending message instead.
    try do
      new_message["say_text"]
      |> parse_command()
      |> execute_command(new_message)
    rescue
      e ->
        Logger.error(
          "[bldg command executor] command failed: #{Exception.message(e)} for say_text=#{inspect(new_message["say_text"])}"
        )
    end

    {:noreply, state}
  end
end
