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
      bldg_url = "#{flr_url}#{Buildings.address_delimiter}#{name}"
      bldg = Buildings.get_by_bldg_url(bldg_url)
      # verify that the speaker is also an owner
      if Enum.find(bldg.owners, fn x -> x == msg["resident_email"] end) == nil do
        raise "Unauthorized"
      else
        Buildings.update_bldg(bldg, %{"owners" => [email | bldg.owners]})
        IO.puts("owner added to bldg #{bldg_url}: #{email}")
      end
    end

    def execute_command(["/remove", "owner", email, "from", "bldg", name], msg) do
      flr_url = msg["say_flr_url"]
      bldg_url = "#{flr_url}#{Buildings.address_delimiter}#{name}"
      bldg = Buildings.get_by_bldg_url(bldg_url)
      # verify that the speaker is also an owner
      if Enum.find(bldg.owners, fn x -> x == msg["resident_email"] end) == nil do
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
    def execute_command(["/connect", "between", name1, "and", name2], msg) do
        # create a road between the given bldgs, inside the given flr

        # validate that the actor resident/bldg has the sufficient permissions
        container_bldg = Buildings.get_flr_bldg(msg["say_flr"]) |> Buildings.get_bldg!()
        if Enum.find(container_bldg.owners, fn x -> x == msg["resident_email"] end) == nil do
          raise "#{msg["resident_email"]} is not authorized to create roads inside #{container_bldg.web_url}"
        else
          # TODO return proper errors
          flr_url = msg["say_flr_url"]
          bldg1_url = "#{flr_url}#{Buildings.address_delimiter}#{name1}"
          bldg1 = Buildings.get_by_bldg_url(bldg1_url)
          from_addr = bldg1.address
          {from_x, from_y} = Buildings.extract_coords(from_addr)
          bldg2_url = "#{flr_url}#{Buildings.address_delimiter}#{name2}"
          bldg2 = Buildings.get_by_bldg_url(bldg2_url)
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
            "owners" => [msg["resident_email"]]
          }
          Relations.create_road(road)
        end
    end

    def fetch_data(data_url) do
      case data_url do
        "" -> ""
        _ ->
          # Check if data_url starts with redis:// or http://
          protocol = cond do
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
          {:ok, data} = Redix.command(:redix, ["GET", data_url])
          data
      end
    end

    def create_bldg_from_command(entity_type, name, website, summary, category, picture_url, data_url, msg) do
      # create a bldg with the given entity-type & name, inside the given flr & bldg

      # validate that the actor resident/bldg has the sufficient permissions
      container_bldg = Buildings.get_flr_bldg(msg["say_flr"]) |> Buildings.get_bldg!()
      if Enum.find(container_bldg.owners, fn x -> x == msg["resident_email"] end) == nil do
        raise "#{msg["resident_email"]} is not authorized to create bldgs inside #{container_bldg.web_url}"
      else
        # TODO if creating under a given bldg, send its container_web_url instead of flr

        data = fetch_data(data_url)

        {x, y} = Buildings.extract_coords(msg["say_location"]) |> Buildings.move_from_speaker(-4)
        flr = msg["say_flr"]
        updated_location = "#{flr}#{Buildings.address_delimiter}b(#{x},#{y})"
        entity = %{
          "flr" => flr,
          "flr_url" => msg["say_flr_url"],
          "address" => updated_location,
          "x" => x,
          "y" => y,
          "name" => name,
          "entity_type" => entity_type,
          "web_url" => website,
          "summary" => summary,
          "category" => category,
          "picture_url" => picture_url,
          "data" => data,
          "state" =>  "approved",
          "owners" => [msg["resident_email"]]
        }
        Buildings.build(entity)
        |> Buildings.create_bldg()
      end
    end


    # create bldg with: name
    def execute_command(["/create", entity_type, "bldg", "with", "name", name], msg) do
      website = ""
      summary = ""
      category = ""
      picture_url = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, summary, category, picture_url, data_url, msg)
    end


    # create bldg with: name & website
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "website", website], msg) do
      # create a bldg with the given entity-type & name, inside the given flr & bldg
      summary = ""
      category = ""
      picture_url = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, summary, category, picture_url, data_url, msg)
    end


    # create bldg with: name & summary
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "summary" | summary_tokens], msg) do
      # create a bldg with the given entity-type, name & summary, inside the given flr & bldg
      website = ""
      category = ""
      picture_url = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, Enum.join(summary_tokens, " "), category, picture_url, data_url, msg)
    end

    # create bldg with: name, category & summary
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "category", category, "and", "summary" | summary_tokens], msg) do
      # create a bldg with the given entity-type, name, category & summary, inside the given flr & bldg
      website = ""
      picture_url = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, Enum.join(summary_tokens, " "), category, picture_url, data_url, msg)
    end

    # create bldg with: name, website, category & summary
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "website", website, "and", "category", category, "and", "summary" | summary_tokens], msg) do
      # create a bldg with the given entity-type, name, category & summary, inside the given flr & bldg
      picture_url = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, Enum.join(summary_tokens, " "), category, picture_url, data_url, msg)
    end

    # create bldg with: name, website, category, data_url & summary
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "website", website, "and", "category", category, "and", "data_url", data_url, "and", "summary" | summary_tokens], msg) do
    # create a bldg with the given entity-type, name, category & summary, inside the given flr & bldg
      picture_url = ""
      create_bldg_from_command(entity_type, name, website, Enum.join(summary_tokens, " "), category, picture_url, data_url, msg)
    end


    # create bldg with: name, website & summary
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "website", website, "and", "summary" | summary_tokens], msg) do
      # create a bldg with the given entity-type, name, website & summary, inside the given flr & bldg
      category = ""
      picture_url = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, Enum.join(summary_tokens, " "), category, picture_url, data_url, msg)
    end

    # create bldg with: name, website, data_url & summary
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "website", website, "and", "data_url", data_url, "and", "summary" | summary_tokens], msg) do
      # create a bldg with the given entity-type, name, website, data_url & summary, inside the given flr & bldg
      category = ""
      picture_url = ""
      create_bldg_from_command(entity_type, name, website, Enum.join(summary_tokens, " "), category, picture_url, data_url, msg)
    end


    # create bldg with: name, picture & summary
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "picture", picture_url, "and", "summary" | summary_tokens], msg) do
      # create a bldg with the given entity-type, name, website & picture url, inside the given flr & bldg
      website = ""
      category = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, Enum.join(summary_tokens, " "), category, picture_url, data_url, msg)
    end

    # create bldg with: name, picture
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "picture", picture_url], msg) do
      # create a bldg with the given entity-type, name, website & picture url, inside the given flr & bldg
      website = ""
      category = ""
      summary = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, summary, category, picture_url, data_url, msg)
    end

    # create bldg with: name, website & picture
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "website", website, "and", "picture", picture_url], msg) do
      # create a bldg with the given entity-type, name, website & picture url, inside the given flr & bldg
      category = ""
      summary = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, summary, category, picture_url, data_url, msg)
    end

    # create bldg with: name, website, picture & summary
    def execute_command(["/create", entity_type, "bldg", "with", "name", name, "and", "website", website, "and", "picture", picture_url, "and", "summary" | summary_tokens], msg) do
      # create a bldg with the given entity-type, name, website & picture url, inside the given flr & bldg
      category = ""
      data_url = ""
      create_bldg_from_command(entity_type, name, website, Enum.join(summary_tokens, " "), category, picture_url, data_url, msg)
    end

    # move bldg
    def execute_command(["/move", "bldg", name, "here"], msg) do
      # update the location of the bldg with the given name to the say location
      # TODO composite bldgs should update the location of their children bldgs as well
      {x, y} = Buildings.extract_coords(msg["say_location"])
      flr_url = msg["say_flr_url"]
      bldg_url = "#{flr_url}#{Buildings.address_delimiter}#{name}"
      bldg = Buildings.get_by_bldg_url(bldg_url)
      # verify that the speaker is also an owner
      if Enum.find(bldg.owners, fn x -> x == msg["resident_email"] end) == nil do
        raise "Unauthorized"
      else
        Buildings.update_bldg(bldg, %{"address" => msg["say_location"], "x" => x, "y" => y})
      end
    end


    # relocate bldg
    def execute_command(["/relocate", "bldg", bldg_url, "here"], msg) do
      # update the bldg_url & address of the bldg with the given bldg_url to the say location
      # TODO composite bldgs should update the location of their children bldgs as well
      # TODO handle location collisions
      {x, y} = Buildings.extract_coords(msg["say_location"])
      name = Buildings.extract_name(bldg_url)
      flr_url = msg["say_flr_url"]
      new_bldg_url = "#{flr_url}#{Buildings.address_delimiter}#{name}"
      bldg = Buildings.get_by_bldg_url(bldg_url)
      container_bldg_url = Buildings.get_container(flr_url)
      container_bldg = Buildings.get_by_bldg_url(container_bldg_url)
      case {bldg,  container_bldg} do
        {nil, _} ->
          IO.puts("Bldg given to relocate couldn't be found: #{bldg_url}")
        {_, nil} ->
          IO.puts("Container of bldg given to relocate couldn't be found: #{container_bldg_url}")
        _ ->
          attrs = %{
            "bldg_url" => new_bldg_url,
            "address" => msg["say_location"],
            "x" => x,
            "y" => y,
            "flr" => msg["say_flr"],
            "flr_url" => flr_url,
            "nesting_depth" => container_bldg.nesting_depth + 1,
            "flr_level" => Buildings.extract_flr_level(msg["say_flr"])
          }
          # verify that the speaker is also an owner
          if Enum.find(bldg.owners, fn x -> x == msg["resident_email"] end) == nil do
            raise "Unauthorized"
          else
            # TODO address may not be exactly the say_location
            Buildings.update_bldg(bldg, attrs)
          end
      end
    end


    # promote bldg inside
    def execute_command(["/promote", "bldg", name, "inside"], msg) do
      # get speaker location (we'll need it to determine which wallpaper to set)
      {x, y} = Buildings.extract_coords(msg["say_location"])
      # get the promoted bldg
      flr_url = msg["say_flr_url"]
      bldg_url = "#{flr_url}#{Buildings.address_delimiter}#{name}"
      bldg = Buildings.get_by_bldg_url(bldg_url)
      picture_url = bldg.picture_url
      cond do
        picture_url == nil -> raise "Promoted entity has no picture URL"
        true ->
            # determine nearest wallpaper
            wallpaper_num = determine_wallpaper_based_on_location(x, y)
            # get the container bldg
            container_bldg_url = Buildings.get_container(flr_url)
            container = Buildings.get_by_bldg_url(container_bldg_url)
            {_, data} = Jason.decode(container.data || "{}")
            {_, new_data} = Map.merge(data, %{"promoted-inside-#{wallpaper_num}-picture-url" => bldg.picture_url}) |> Jason.encode()
            # update bldg
            Buildings.update_bldg(container, %{"data" => new_data})
        end
    end


    # demote bldg inside
    def execute_command(["/demote", "bldg", name, "inside"], msg) do
      # get the promoted bldg
      flr_url = msg["say_flr_url"]
      bldg_url = "#{flr_url}#{Buildings.address_delimiter}#{name}"
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
            data_key = data
            |> Enum.find(fn {_, val} -> val == picture_url end)
            |> elem(0)
            # TODO check that key exists
            {_, new_data} = Map.delete(data, data_key) |> Jason.encode()
            # update bldg
            Buildings.update_bldg(container, %{"data" => new_data})
        end
    end

    def execute_command(msg_parts, _msg) do
      Logger.info("Ignoring unknown command:")
      IO.inspect(msg_parts)
    end

    #def handle_info({sender, message, flr}, state) do
    def handle_info(%{event: "new_message", payload: new_message}, state) do
      #Logger.info("chat message received at #{flr} from #{sender}: #{message}")
      Logger.info("~~~~~~~~~~~~ [bldg command executor] chat message received: #{new_message["message"]}")

      new_message["say_text"]
      |> parse_command()
      |> execute_command(new_message)

      {:noreply, state}
    end
  end
