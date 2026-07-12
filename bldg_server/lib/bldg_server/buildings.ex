defmodule BldgServer.Buildings do
  @moduledoc """
  The Buildings context.
  """

  import Ecto.Query, warn: false, only: [from: 2]
  require Logger
  alias BldgServer.Repo

  alias BldgServer.Buildings.Bldg

  @default_visual_language %{
    "ground" => %{"3d_object" => "ground", "flr_height" => "1.08", "flr0_height" => "0.01"},
    "stage" => %{"3d_object" => "stage", "flr_height" => "0.9", "flr0_height" => "0.022"},
    "enabler" => %{"3d_object" => "blueLot", "flr_height" => "0.9", "flr0_height" => "0.022"},
    "milestone" => %{"3d_object" => "raceGate", "flr_height" => "0.9", "flr0_height" => "0.022"},
    "metric" => %{"3d_object" => "metricDisplay", "flr_height" => "0.9", "flr0_height" => "0.022"},
    "task" => %{"3d_object" => "greenLot", "flr_height" => "0.9", "flr0_height" => "0.022"},
    "team" => %{"3d_object" => "buildingWithStorefront", "flr_height" => "0.9", "flr0_height" => "0.05"},
    "storage" => %{"3d_object" => "storageBuilding", "flr_height" => "0.7", "flr0_height" => "0.03"},
    "costs" => %{"3d_object" => "chestOfDrawers", "flr_height" => "2.57", "flr0_height" => "0.067"},
    "inbox" => %{"3d_object" => "tray", "flr_height" => "2.57", "flr0_height" => "0.067"},
    "sales" => %{"3d_object" => "bookCabinet", "flr_height" => "0.5", "flr0_height" => "-0.12"},
    "goal" => %{"3d_object" => "livingRoomTable", "flr_height" => "1.08", "flr0_height" => "1.11"},
    "purpose" => %{"3d_object" => "whiteboard"},
    "cantata" => %{"3d_object" => "presentationStand"},
    "heading" => %{"3d_object" => "trafficSign"},
    "name" => %{"3d_object" => "streetSign"},
    "construction" => %{"3d_object" => "construction"},
    "age" => %{"3d_object" => "tree"},
    "delivery" => %{"3d_object" => "tree"},
    "solution" => %{"3d_object" => "couch"},
    "product" => %{"3d_object" => "sofa"},
    "service" => %{"3d_object" => "fancyChair"},
    "capability" => %{"3d_object" => "coffeeTableChair"},
    "member" => %{"3d_object" => "standingLight"},
    "customer" => %{"3d_object" => "candle"},
    "community" => %{"3d_object" => "fireplace"},
    "project" => %{"3d_object" => "tree"},
    "action" => %{"3d_object" => "largePottedPlant"},
    "equity" => %{"3d_object" => "tableWithDrawers"},
    "agreement" => %{"3d_object" => "owlSculpture"},
    "decision" => %{"3d_object" => "headSculpture"},
    "person" => %{"3d_object" => "person"},
    "agent" => %{"3d_object" => "agent"},
    "battery" => %{"3d_object" => "tv"},
    "ai-chat" => %{"3d_object" => "documentDisplay"},
    "artifact" => %{"3d_object" => "documentDisplay"},
    "description" => %{"3d_object" => "whiteboard"},
    "label" => %{"3d_object" => "flag_blue"},
    "yellow-lot" => %{"3d_object" => "yellowLot"},
    "storage-box" => %{"3d_object" => "storageBox"},
    "large-storage-box" => %{"3d_object" => "largeStorageBox"},
    "inactive-person" => %{"3d_object" => "inactivePerson"}
  }

  def default_visual_language, do: @default_visual_language

  def address_delimiter, do: "/"

  @doc """
  Returns the list of bldgs.

  ## Examples

      iex> list_bldgs()
      [%Bldg{}, ...]

  """
  def list_bldgs do
    Repo.all(Bldg)
  end

  @doc """
  Returns all bldgs under a given flr.

  Returns empty list if no such Bldg does exists.
  """
  def list_bldgs_in_flr(flr) do
    q = from(b in Bldg, where: b.flr == ^flr)
    Repo.all(q)
  end

  def list_all_bldgs_in_flr(flr, include_parent) do
    # 1. Resolve the parent address only if needed.
    # If include_parent is false, we set parent_addr to nil.
    parent_addr = if include_parent, do: get_flr_bldg(flr), else: ""

    # Delimiter-safe: match the floor exactly (direct children) or a strict
    # sub-path ("flr/..."). A bare "flr%" prefix would also match a numerically-
    # prefixed sibling floor (e.g. ".../l1" wrongly matching ".../l10").
    q =
      from(b in Bldg,
        where:
          b.flr == ^flr or like(b.flr, ^"#{flr}/%") or
            (^include_parent and b.address == ^parent_addr)
      )

    bldgs = Repo.all(q)
    IO.puts("~~~ scan returned #{Enum.count(bldgs)} bldgs")
    bldgs
  end

  def list_all_bldgs_in_flr(flr) do
    list_all_bldgs_in_flr(flr, false)
  end

  @doc """
  Gets a single bldg.

  Raises `Ecto.NoResultsError` if the Bldg does not exist.

  ## Examples

      iex> get_bldg!(123)
      %Bldg{}

      iex> get_bldg!(456)
      ** (Ecto.NoResultsError)

  """
  def get_bldg!(address), do: Repo.get_by!(Bldg, address: address)

  def get_by_web_url(url), do: Repo.get_by(Bldg, web_url: url)

  def get_by_bldg_url(bldg_url), do: Repo.get_by(Bldg, bldg_url: bldg_url)

  def get_similar_entities(flr, entity_type) do
    q =
      from(b in Bldg,
        where: b.flr == ^flr and b.entity_type == ^entity_type,
        order_by: b.inserted_at,
        limit: 10
      )

    Repo.all(q)
  end

  def notify_bldg_created(
        {:error,
         %BldgServer.Buildings.Bldg{name: name, flr: container_flr, flr_url: container_flr_url}},
        action,
        subject,
        triggering_chat_msg
      ) do
    # recursive call, no need to extract location from subject
    IO.puts("Recursive call to notify on bldg-creation-failure: #{:error}")
    action = "failed_to_create_bldg"
    container_addr = get_container(container_flr)

    if container_addr != "" do
      # TODO handle the case where the container is g
      container = get_bldg!(container_addr)

      msg = %{
        "say_speaker" => "bldg_server",
        "say_text" => "/notify #{action} done: #{subject}",
        "action_type" => "SAY",
        "bldg_url" => "",
        "say_flr" => container_flr,
        "say_flr_url" => container_flr_url,
        "say_mimetype" => "text/plain",
        "say_recipient" => "",
        "say_time" => 0,
        "resident_email" => "bldg_server",
        "say_location" => ""
      }

      say(container, msg)
      # recurse to parent container
      notify_bldg_created({:error, container}, action, subject, triggering_chat_msg)
    end
  end

  def notify_bldg_created({:error, error_description}, action, subject, triggering_chat_msg) do
    # errors: [address: {"has already been taken", [constraint: :unique, constraint_name: "bldgs_address_index"]}], data: #BldgServer.Buildings.Bldg<>, valid?: false>
    # Check if error is due to address constraint violation
    is_address_constraint =
      case error_description do
        %{errors: errors} ->
          Enum.any?(errors, fn {field, {_msg, details}} ->
            field == :address &&
              Keyword.get(details, :constraint) == :unique &&
              Keyword.get(details, :constraint_name) == "bldgs_address_index"
          end)

        _ ->
          false
      end

    if is_address_constraint do
      IO.puts("~~~~~ Error: Address constraint violation detected, retrying create command")
      # let's retry this chat command - up to 10 times - by broadcasting the message again
      # Extract and modify coordinates for retry
      case triggering_chat_msg do
        %{"say_location" => location} = msg when is_binary(location) ->
          # Jitter the last segment's coords (clamped >= 0), rewriting only that
          # segment — not the first textual match — to avoid corrupting an
          # ancestor segment sharing the same coords.
          new_location = jitter_bldg_location(location)
          new_msg = Map.put(msg, "say_location", new_location)
          IO.puts("~~~~~ Retrying with new location: #{new_location} (moved from #{location})")

          BldgServerWeb.Endpoint.broadcast!(
            "chat",
            "new_message",
            new_msg
          )

        # Return unchanged if no location or wrong format
        msg ->
          msg
      end
    end

    IO.puts("~~~~~ 1st call to notify on bldg creation error: #{inspect(error_description)}")
    # notification parameters
    # extract location from subject
    IO.puts("~~~~~ at notify_bldg_created - FAILURE: #{subject}")
    [bldg_url, address, web_url] = String.split(subject, "|")
    container_flr = get_container_flr(address)
    IO.puts("~~~~ in notify_bldg_created - FAILURE - container_flr: #{inspect(container_flr)}")
    container_flr_url = get_container(bldg_url)

    IO.puts(
      "~~~~ in notify_bldg_created - FAILURE - container_flr_url: #{inspect(container_flr_url)}"
    )

    action = "failed_to_create_bldg"
    container_addr = get_container(container_flr)

    if container_addr != "" do
      # TODO handle the case where the container is g
      container = get_bldg!(container_addr)

      msg = %{
        "say_speaker" => "bldg_server",
        "say_text" => "/notify #{action} done: #{subject}",
        "action_type" => "SAY",
        "bldg_url" => "",
        "say_flr" => container_flr,
        "say_flr_url" => container_flr_url,
        "say_mimetype" => "text/plain",
        "say_recipient" => "",
        "say_time" => 0,
        "resident_email" => "bldg_server",
        "say_location" => ""
      }

      say(container, msg)
      # recurse to parent container
      notify_bldg_created({:error, container}, action, subject, triggering_chat_msg)
    end
  end

  def notify_bldg_created({:ok, created_bldg}, action, subject, triggering_chat_msg) do
    # notification parameters
    %BldgServer.Buildings.Bldg{name: name, address: address, flr: container_flr, flr_url: container_flr_url, owners: owners} =
      created_bldg

    resident_email = List.first(owners || []) || "bldg_server"

    IO.puts("~~~~~ at notify_bldg_created - SUCCESS: #{name}")
    container_addr = if container_flr == "g", do: "g", else: get_container(container_flr)
    IO.puts("~~~~ container_addr: #{inspect(container_addr)}")

    # Stop at the root: the ground floor sits on itself (flr "g" -> container_addr
    # "g", which equals its own address), so without the `!= address` guard the
    # walk recurses into the ground floor forever.
    if container_addr != "" and container_addr != address do
      container = get_bldg!(container_addr)

      msg = %{
        "say_speaker" => "bldg_server",
        "say_text" => "/notify #{action} done: #{subject}",
        "action_type" => "SAY",
        "bldg_url" => "",
        "say_flr" => container_flr,
        "say_flr_url" => container_flr_url,
        "say_mimetype" => "text/plain",
        "say_recipient" => "",
        "say_time" => 0,
        "resident_email" => resident_email,
        "say_location" => ""
      }

      say(container, msg)
      # recurse to parent container
      notify_bldg_created({:ok, container}, action, subject, triggering_chat_msg)
    end
  end

  def notify_bldg_updated({:error, _} = error_result, _, subject, _) do
    IO.puts("~~~~~ at notify_bldg_updated - FAILURE: #{subject}")
    # Pass the error changeset through so update_bldg/2 preserves the
    # {:error, changeset} contract instead of returning the IO.puts result.
    error_result
  end

  def notify_bldg_updated({:ok, updated_bldg} = update_result, action, subject, attrs) do
    # notification parameters
    %BldgServer.Buildings.Bldg{name: name, address: address, flr: container_flr, flr_url: container_flr_url, owners: owners} =
      updated_bldg

    resident_email = List.first(owners || []) || "bldg_server"

    IO.puts("~~~~~ at notify_bldg_updated #{action} - SUCCESS: #{name}")
    container_addr = if container_flr == "g", do: "g", else: get_container(container_flr)
    IO.puts("~~~~ container_addr: #{inspect(container_addr)}")

    # Stop at the root: see notify_bldg_created/4 — guard against the ground
    # floor (container_addr == its own address) to avoid infinite recursion.
    if container_addr != "" and container_addr != address do
      container = get_bldg!(container_addr)

      msg = %{
        "say_speaker" => "bldg_server",
        "say_text" => "/notify #{action} done: #{subject}",
        "action_type" => "SAY",
        "bldg_url" => "",
        "say_flr" => container_flr,
        "say_flr_url" => container_flr_url,
        "say_mimetype" => "text/plain",
        "say_recipient" => "",
        "say_time" => 0,
        "resident_email" => resident_email,
        "say_location" => ""
      }

      say(container, msg)
      # recurse to parent container
      notify_bldg_updated({:ok, container}, action, subject, attrs)
    end

    update_result
  end

  @doc """
  Creates a bldg.

  ## Examples

      iex> create_bldg(%{field: value})
      {:ok, %Bldg{}}

      iex> create_bldg(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_bldg(attrs, triggering_chat_msg \\ %{}) do
    IO.puts("~~~~ create_bldg called")

    cs =
      %Bldg{}
      |> Bldg.changeset(attrs)
      |> reject_if_overlapping()

    # TODO figure out better way to notify bldg_url & address
    created_bldg_url = attrs["bldg_url"]
    created_bldg_address = attrs["address"]
    # the "natural key" of the entity
    created_bldg_web_url = attrs["web_url"]
    created_bldg_ids = "#{created_bldg_url}|#{created_bldg_address}|#{created_bldg_web_url}"

    case cs.errors do
      [] ->
        result = Repo.insert(cs)

        # FAIL LOUD: command execution is async, so the HTTP caller already got
        # its 200 — a failed INSERT must be logged clearly here or it vanishes
        # silently (the "artifact created but never rendered" class of bug).
        case result do
          {:error, failed_cs} ->
            Logger.error(
              "Failed to create bldg #{inspect(created_bldg_url)}: " <>
                "#{inspect(failed_cs.errors)}"
            )

          _ ->
            :ok
        end

        notify_bldg_created(result, "bldg_created", created_bldg_ids, triggering_chat_msg)
        broadcast_bldg_change(result, "bldg_created")
        result

      _ ->
        # Return the invalid changeset (the conventional Ecto contract) instead
        # of raising, so callers like BldgController.create/2 — which already
        # pattern-match {:error, _} — can render a 422 rather than 500.
        Logger.error("Failed to prepare bldg for writing to database: #{inspect(cs.errors)}")
        {:error, cs}
    end
  end

  # Reject a create whose footprint would overlap an existing bldg on the same
  # floor. Auto-placement already avoids this (find_free_footprint chooses a
  # clear slot); this guards the *explicit*-placement path — where a caller
  # supplies exact coords — since the unique-address constraint only catches an
  # identical origin, not a partial footprint overlap.
  defp reject_if_overlapping(%Ecto.Changeset{valid?: false} = cs), do: cs

  defp reject_if_overlapping(cs) do
    flr = Ecto.Changeset.get_field(cs, :flr)
    x = Ecto.Changeset.get_field(cs, :x)
    y = Ecto.Changeset.get_field(cs, :y)
    width = Ecto.Changeset.get_field(cs, :width) || 1
    height = Ecto.Changeset.get_field(cs, :height) || 1

    if is_binary(flr) and is_integer(x) and is_integer(y) do
      candidate = %{x: x, y: y, width: width, height: height}

      if Enum.any?(occupied_footprints(flr), &footprints_overlap?(candidate, &1)) do
        Ecto.Changeset.add_error(cs, :address, "footprint overlaps an existing bldg on this floor")
      else
        cs
      end
    else
      cs
    end
  end

  @doc """
  Updates a bldg.

  ## Examples

      iex> update_bldg(bldg, %{field: new_value})
      {:ok, %Bldg{}}

      iex> update_bldg(bldg, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_bldg(%Bldg{} = bldg, attrs) do
    IO.puts("~~~~ updating bldg #{bldg.name} with attrs: #{inspect(attrs)}")

    # TODO figure out better way to notify bldg_url & address
    updated_bldg_url = attrs["bldg_url"]
    updated_bldg_address = attrs["address"]
    # the "natural key" of the entity
    updated_bldg_web_url = attrs["web_url"]
    updated_bldg_ids = "#{updated_bldg_url}|#{updated_bldg_address}|#{updated_bldg_web_url}"

    if Map.has_key?(attrs, :previous_messages) do
      # don't notify on chat updates
      bldg
      |> Bldg.changeset(attrs)
      |> Repo.update()
    else
      old_address = bldg.address
      old_flr = bldg.flr
      old_bldg_url = bldg.bldg_url

      result =
        bldg
        |> Bldg.changeset(attrs)
        |> Repo.update()
        |> notify_bldg_updated("bldg_updated", updated_bldg_ids, attrs)

      broadcast_bldg_change(result, "bldg_updated")

      case result do
        {:ok, %Bldg{address: new_address} = updated} when new_address != old_address ->
          # Re-home every nested descendant onto the moved subtree, then fix up
          # roads connected to the container itself.
          relocate_bldg_cascade(old_address, old_bldg_url, updated)
          BldgServer.Relations.cascade_bldg_relocation(old_address, old_flr, updated)
        _ ->
          :ok
      end

      result
    end
  end

  @doc """
  Deletes a bldg.

  ## Examples

      iex> delete_bldg(bldg)
      {:ok, %Bldg{}}

      iex> delete_bldg(bldg)
      {:error, %Ecto.Changeset{}}

  """
  def delete_bldg(%Bldg{} = bldg) do
    # Capture flr and id before deletion for the broadcast
    flr = bldg.flr
    bldg_id = bldg.id
    result = Repo.delete(bldg)

    case result do
      {:ok, _} ->
        broadcast_to_floor_and_ancestors(flr, "bldg_deleted", %{id: bldg_id})
      _ ->
        :ok
    end

    result
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking bldg changes.

  ## Examples

      iex> change_bldg(bldg)
      %Ecto.Changeset{source: %Bldg{}}

  """
  def change_bldg(%Bldg{} = bldg) do
    Bldg.changeset(bldg, %{})
  end

  @doc """
  Appends a favorite view-point to a bldg's list.

  `attrs` is a map with string keys: "name", "address", "direction",
  "size_delta", "camera_vertical_angle".
  """
  def add_favorite_view_point(%Bldg{} = bldg, attrs) do
    view_point = %{
      "name" => attrs["name"],
      "address" => attrs["address"],
      "direction" => attrs["direction"],
      "size_delta" => attrs["size_delta"],
      "camera_vertical_angle" => attrs["camera_vertical_angle"]
    }

    updated = (bldg.favorite_view_points || []) ++ [view_point]
    update_bldg(bldg, %{favorite_view_points: updated})
  end

  @doc """
  Deletes a bldg and all nested children (cascade).
  Deletes deepest children first, then roads, then the target bldg.
  Each deletion broadcasts its own bldg_deleted/road_deleted event.
  """
  def delete_bldg_cascade(%Bldg{} = bldg) do
    # Find all nested child bldgs
    children = list_all_bldgs_in_flr(bldg.address)

    # Delete deepest children first
    children
    |> Enum.sort_by(& &1.nesting_depth, :desc)
    |> Enum.each(fn child ->
      # Delete roads on the child's floors
      BldgServer.Relations.list_all_roads_in_flr(child.address)
      |> Enum.each(&BldgServer.Relations.delete_road/1)

      delete_bldg(child)
    end)

    # Delete roads on the target bldg's floors
    BldgServer.Relations.list_all_roads_in_flr(bldg.address)
    |> Enum.each(&BldgServer.Relations.delete_road/1)

    # Delete the target bldg itself
    delete_bldg(bldg)
  end

  @doc """
  Re-homes every nested descendant of a relocated container.

  When a container bldg moves (`old_address`/`old_bldg_url` -> the moved bldg's
  new address/bldg_url), each descendant's `address`/`flr` is rebased on the new
  *address* root and its `bldg_url`/`flr_url` on the new *bldg_url* root (the two
  hierarchies differ when the container is name-aliased). Roads on descendant
  floors have their `flr`/`from_address`/`to_address` rebased too — their endpoint
  coords are floor-local and so are preserved. Everything is updated directly (no
  re-cascade) and re-broadcast on its new floor.
  """
  def relocate_bldg_cascade(old_address, old_bldg_url, %Bldg{} = moved) do
    old_addr_root = BldgServer.Address.parse!(old_address)
    new_addr_root = BldgServer.Address.parse!(moved.address)
    old_url_root = BldgServer.Address.parse!(old_bldg_url)
    new_url_root = BldgServer.Address.parse!(moved.bldg_url)

    old_address
    |> list_all_bldgs_in_flr()
    |> Enum.each(fn d ->
      attrs = %{
        "address" => rebase_segment(d.address, old_addr_root, new_addr_root),
        "flr" => rebase_segment(d.flr, old_addr_root, new_addr_root),
        "bldg_url" => rebase_segment(d.bldg_url, old_url_root, new_url_root),
        "flr_url" => rebase_segment(d.flr_url, old_url_root, new_url_root)
      }

      d
      |> Bldg.changeset(attrs)
      |> Repo.update()
      |> broadcast_bldg_change("bldg_updated")
    end)

    # Roads on descendant floors: rebase the floor + endpoint addresses (all
    # address-based); from_x/from_y/to_x/to_y are floor-local and unchanged.
    old_address
    |> BldgServer.Relations.list_all_roads_in_flr()
    |> Enum.each(fn road ->
      attrs = %{
        "flr" => rebase_segment(road.flr, old_addr_root, new_addr_root),
        "from_address" => rebase_segment(road.from_address, old_addr_root, new_addr_root),
        "to_address" => rebase_segment(road.to_address, old_addr_root, new_addr_root)
      }

      BldgServer.Relations.update_road(road, attrs)
    end)
  end

  # Rebase a single address/url string under a moved root, leaving it untouched
  # if it doesn't actually sit under that root.
  defp rebase_segment(str, from_root, to_root) do
    case BldgServer.Address.rebase(BldgServer.Address.parse!(str), from_root, to_root) do
      :error -> str
      rebased -> BldgServer.Address.to_string(rebased)
    end
  end

  defp broadcast_bldg_change({:ok, %Bldg{} = bldg}, event) do
    payload = BldgServerWeb.FloorChannel.serialize_bldg(bldg)
    broadcast_to_floor_and_ancestors(bldg.flr, event, payload)
  end

  defp broadcast_bldg_change(_, _), do: :ok

  @doc """
  Broadcasts an event to a floor topic and all ancestor floor topics.
  This ensures clients doing recursive scans (viewing a base floor) receive
  events from nested floors.

  For example, a change on floor "g/b(1,2)/l0/b(3,4)/l0" broadcasts to:
  - "floor:g/b(1,2)/l0/b(3,4)/l0"
  - "floor:g/b(1,2)/l0"
  - "floor:g"
  """
  def broadcast_to_floor_and_ancestors(flr, event, payload) do
    # Broadcast to the direct floor
    BldgServerWeb.Endpoint.broadcast!("floor:#{flr}", event, payload)

    # Walk up ancestor floors
    parts = String.split(flr, address_delimiter())
    broadcast_ancestor_floors(parts, event, payload)
  end

  defp broadcast_ancestor_floors(parts, event, payload) when length(parts) <= 1, do: :ok

  defp broadcast_ancestor_floors(parts, event, payload) do
    # Remove the last 2 segments (bldg + floor) to get to the parent floor
    # e.g., ["g", "b(1,2)", "l0", "b(3,4)", "l0"] -> ["g", "b(1,2)", "l0"] -> ["g"]
    parent_parts = Enum.slice(parts, 0, length(parts) - 2)
    parent_flr = Enum.join(parent_parts, address_delimiter())

    if parent_flr != "" do
      BldgServerWeb.Endpoint.broadcast!("floor:#{parent_flr}", event, payload)
      broadcast_ancestor_floors(parent_parts, event, payload)
    end
  end

  # This didn't work - update wasn't really applied
  # def update_containers({:ok, %Bldg{} = bldg}) do
  #   # Update the updated_at field of all containers of
  #   # the given bldg
  #   IO.puts("~~~~ updating containers called for bldg: #{bldg.name}")
  #   container_addr = get_container(bldg.flr)
  #   IO.puts("~~~~ the container_addr of #{bldg.name} is: #{inspect(container_addr)}")
  #   if container_addr != "" do
  #     get_bldg!(container_addr)
  #     |> update_bldg(%{"updated_at" => DateTime.utc_now()})
  #     |> update_containers() #  continue recursively to next container
  #   end
  # end

  # UTILS

  def extract_coords(addr) do
    # Delegates to the parsed Address. The {x, y} match preserves the historical
    # raise-on-malformed contract: a non-bldg-terminated address has no coords.
    {x, y} = BldgServer.Address.coords(BldgServer.Address.parse!(addr))
    {x, y}
  end

  def extract_flr_level(flr) do
    case BldgServer.Address.floor_level(BldgServer.Address.parse!(flr)) do
      level when is_integer(level) -> level
      :error -> raise ArgumentError, "no floor level in address #{inspect(flr)}"
    end
  end

  def extract_name(bldg_url) do
    bldg_url |> String.split(address_delimiter()) |> List.last()
  end

  def move_from_speaker({x, y}, offset) do
    {x, y + offset}
  end

  def get_container(""), do: ""

  def get_container(addr) do
    case BldgServer.Address.container(BldgServer.Address.parse!(addr)) do
      :error -> ""
      container -> BldgServer.Address.to_string(container)
    end
  end

  def get_container_flr(addr) do
    # returns the container flr for given address.
    # TODO verify that a bldg is given & not a flr
    # TODO if addr is g, return g? null?
    get_container(addr)
  end

  def get_container_flr_url(bldg_url) do
    # returns the container flr url for given bldg url.
    # TODO verify that a bldg is given & not a flr
    # TODO if bldg url is g, return g? null?
    get_container(bldg_url)
  end

  def get_flr_bldg(flr) do
    case flr do
      "g" -> "g"
      _ -> get_container(flr)
    end
  end

  @doc """
  Checks whether the given email is an authorized owner of the building,
  either directly or via ownership of any ancestor (container) building.
  Ownership is inherited: if you own a building, you can operate on
  everything nested inside it.
  """
  def is_authorized_owner?(email, %Bldg{} = bldg) do
    if owner_match?(email, bldg.owners) do
      true
    else
      # Walk up the container chain by bldg_url
      walk_up_owners(email, bldg.bldg_url)
    end
  end

  def is_authorized_owner?(_email, nil), do: false

  # Email ownership is matched case-insensitively and whitespace-trimmed:
  # mailbox auth (magic link) makes "A@x.com" and "a@x.com" the same recipient,
  # so the check must not be bypassable by — nor falsely deny on — casing or a
  # stray trailing space in either the claimed email or a stored owner entry.
  defp owner_match?(nil, _owners), do: false

  defp owner_match?(email, owners) do
    normalized = normalize_email(email)
    normalized != "" and Enum.any?(owners || [], &(normalize_email(&1) == normalized))
  end

  defp normalize_email(nil), do: ""
  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  # Walk up the bldg_url hierarchy, skipping floors (which aren't in the bldgs table)
  defp walk_up_owners(_email, ""), do: false
  defp walk_up_owners(_email, "g"), do: false

  defp walk_up_owners(email, url) do
    parent_url = get_container(url)

    if parent_url == url or parent_url == "" do
      false
    else
      case get_by_bldg_url(parent_url) do
        nil ->
          # Parent is likely a floor (e.g., "g/udi-bauman/l0") — skip and keep walking
          walk_up_owners(email, parent_url)

        parent ->
          if owner_match?(email, parent.owners) do
            true
          else
            walk_up_owners(email, parent_url)
          end
      end
    end
  end

  # FRAMEWORK

  """
  Determines the flr of a new entity to be created
  Calculates the following fields:
  - flr (address)
  - flr_url (bldg_url of the flr)
  -  flr_level (flr number)
  And returns the given entity with these 3 additional fields

  Supports 3 modes:
  1. Receiving just container bldg address -> flr would be l0 on that bldg
  2. Receiving just container bldg url -> flr would be l0 on that bldg
  3. Receiving the flr & flr_url -> no need to figure out, just extract the flr level

  Note that providing just flr or flr_url isn't currently supported.

  TODO simplify
  """

  def figure_out_flr(entity) do
    {flr, flr_url, flr_level} =
      cond do
        Map.has_key?(entity, "container_web_url") ->
          %{"container_web_url" => container} = entity
          entity_bldg = get_by_web_url(container)
          # TODO handle the case the container bldg doesn't exist
          case entity_bldg.address do
            "g" ->
              {"g", "g", 0}

            _ ->
              {"#{entity_bldg.address}#{address_delimiter()}l0",
               "#{entity_bldg.bldg_url}#{address_delimiter()}l0", 0}
          end

        Map.has_key?(entity, "container_bldg_url") ->
          %{"container_bldg_url" => container} = entity
          entity_bldg = Buildings.get_by_bldg_url(container)

          {"#{entity_bldg.address}#{address_delimiter()}l0",
           "#{entity_bldg.bldg_url}#{address_delimiter()}l0", 0}

        Map.has_key?(entity, "flr") and Map.has_key?(entity, "flr_url") ->
          level = extract_flr_level(Map.get(entity, "flr"))
          {Map.get(entity, "flr"), Map.get(entity, "flr_url"), level}

        true ->
          raise "Not enought information to determine where to create the bldg - you need to provide either: container_web_url or container_bldg_url or (flr AND flr_url)"
      end

    entity
    |> Map.put("flr", flr)
    |> Map.put("flr_url", flr_url)
    |> Map.put("flr_level", flr_level)
  end

  def figure_out_bldg_url(entity) do
    bldg_url =
      cond do
        Map.has_key?(entity, "bldg_url") ->
          Map.get(entity, "bldg_url")

        Map.has_key?(entity, "flr_url") and Map.has_key?(entity, "name") ->
          "#{Map.get(entity, "flr_url")}#{address_delimiter()}#{Map.get(entity, "name")}"

        true ->
          raise "Not enought information to determine the bldg URL"
      end

    Map.put(entity, "bldg_url", bldg_url)
  end

  """
  next_location(similar_bldgs)
  1. Go over similar_bldgs, & store their locations in a cache
  2. Sort the cache by location x, y
  2. Go over the cache, & find the start location (sx, sy) - minimal x, minimal y (since origin is bottom left, & we’ll be adding bldgs to the right)
  3. Loop over the possible locations, from sx to max_x, and from sy to max_y, each time checking whether the current location exists in cache
  4. If not, return that location
  5. If finished looping over all possible locations, and sx>0, return the point (sx-1, sy)


  Given an entity:
  1. Loop until reached max retries:
  1.1. Get similar_bldgs
  1.2. Get next_location
  1.3. Try to store the entity in that location
  1.4. If done, return
  1.5. Else, continue the loop
  """

  def get_locations_map(bldgs) do
    Enum.map(bldgs, fn bldg -> {bldg.x, bldg.y} end)
  end

  def get_minimal_location(locations) do
    locations
    |> Enum.sort()
    |> List.first()
  end

  def get_next_available_location(locations, start_location, max_x, max_y) do
    {x, y} = start_location

    found =
      Enum.reduce_while(y..max_y, nil, fn y, _ ->
        options = for i <- x..max_x, do: {i, y}
        whats_available = Enum.map(options, fn loc -> Enum.member?(locations, loc) end)
        pos = Enum.find_index(whats_available, fn b -> !b end)

        case pos do
          nil -> {:cont, nil}
          _ -> {:halt, Enum.at(options, pos)}
        end
      end)

    case found do
      nil ->
        # The up-and-right grid from the cluster's minimal corner is full.
        # Documented fallback (step 5): place one column to the left of the
        # cluster, clamped to >= 0. Returns nil only when there is truly no room
        # (start column already at 0); callers must handle nil rather than crash.
        if x > 0, do: {x - 1, y}, else: nil

      loc ->
        loc
    end
  end

  def get_next_location(similar_bldgs, max_x, max_y) do
    locations = get_locations_map(similar_bldgs)
    start_location = get_minimal_location(locations)
    get_next_available_location(locations, start_location, max_x, max_y)
  end

  defp random_location(max_x, max_y) do
    {:rand.uniform(max_x - 1) + 1, :rand.uniform(max_y - 1) + 1}
  end

  @doc """
  Whether two footprints intersect. Each is a map with `:x`, `:y`, `:width`,
  `:height`; `{x, y}` is the bottom-left origin, covering `x..x+width-1` ×
  `y..y+height-1`.
  """
  def footprints_overlap?(a, b) do
    a.x < b.x + b.width and b.x < a.x + a.width and
      a.y < b.y + b.height and b.y < a.y + a.height
  end

  @doc """
  The footprints of every bldg currently on `flr`.
  """
  def occupied_footprints(flr) do
    Repo.all(
      from(b in Bldg,
        where: b.flr == ^flr,
        select: %{x: b.x, y: b.y, width: b.width, height: b.height}
      )
    )
  end

  @doc """
  The first free `width` x `height` footprint on a `max_x` x `max_y` floor,
  scanning row-major from `{1, 1}` and skipping any origin whose rectangle would
  exceed the floor or intersect one of the `occupied` footprints. Returns a
  `%{x, y, width, height}` map, or `nil` when there is no room.
  """
  def find_free_footprint(occupied, width, height, max_x, max_y) do
    Enum.find_value(1..max_y, fn y ->
      Enum.find_value(1..max_x, fn x ->
        candidate = %{x: x, y: y, width: width, height: height}

        cond do
          x + width - 1 > max_x -> nil
          y + height - 1 > max_y -> nil
          Enum.any?(occupied, &footprints_overlap?(candidate, &1)) -> nil
          true -> candidate
        end
      end)
    end)
  end

  @doc """
  Replaces the coordinates of the *last* bldg segment of an address.

  The bldg's own coords are always the final `b(x,y)` segment, so we target it
  by position rather than by `String.replace/3`, which would rewrite the first
  textual match — corrupting an ancestor segment that happens to share the same
  coords (e.g. `g/b(5,5)/l0/b(5,5)`).
  """
  def replace_bldg_coords(address, new_x, new_y) do
    address
    |> String.split(address_delimiter())
    |> List.replace_at(-1, "b(#{new_x},#{new_y})")
    |> Enum.join(address_delimiter())
  end

  @doc """
  Computes a jittered location for collision-retry: shifts the last segment's
  coords by -1, 0, or +1 on each axis, clamped to >= 0, and rewrites only that
  segment. Returns the new address string.
  """
  def jitter_bldg_location(location) do
    {x, y} = extract_coords(location)
    # :rand.uniform(3) is 1..3, so (… - 2) gives a symmetric -1/0/+1 shift
    # (the original `- 1` only ever shifted right/up by 0/1/2).
    new_x = max(x + :rand.uniform(3) - 2, 0)
    new_y = max(y + :rand.uniform(3) - 2, 0)
    replace_bldg_coords(location, new_x, new_y)
  end

  def decide_on_location(entity) do
    # floor width is: 16
    max_x = 16
    # floor height is: 12
    max_y = 12
    # TODO read from config

    case Map.get(entity, "address") do
      nil ->
        flr = Map.fetch!(entity, "flr")
        width = Map.get(entity, "width", 1)
        height = Map.get(entity, "height", 1)

        # Place the new bldg's footprint clear of every footprint already on the
        # floor. A full floor yields nil; fall back to a random slot and let the
        # unique-address constraint + create retry resolve any residual collision
        # rather than crashing on a {x, y} = nil match.
        {x, y} =
          case find_free_footprint(occupied_footprints(flr), width, height, max_x, max_y) do
            nil -> random_location(max_x, max_y)
            %{x: x, y: y} -> {x, y}
          end

        Map.merge(entity, %{
          "address" => "#{flr}#{address_delimiter()}b(#{x},#{y})",
          "x" => x,
          "y" => y
        })

      _ ->
        entity
    end

    # TODO handle the case where the location is already caught
  end

  def calculate_nesting_depth(entity) do
    depth =
      entity
      |> Map.get("address")
      |> BldgServer.Address.parse!()
      |> BldgServer.Address.nesting_depth()

    Map.put(entity, "nesting_depth", depth)
  end

  def add_composite_bldg_metadata(%{"entity_type" => "ground"} = entity) do
    vl_entry = @default_visual_language["ground"]
    default_data = %{flr_height: vl_entry["flr_height"], flr0_height: vl_entry["flr0_height"]}

    combined_data =
      case Map.get(entity, "data") do
        nil -> default_data
        _ -> Map.merge(default_data, Map.get(entity, "data"))
      end

    {_, data_json} = JSON.encode(combined_data)

    visual_language = Map.get(entity, "visual_language") || @default_visual_language

    entity
    |> Map.put("is_composite", true)
    |> Map.put("data", data_json)
    |> Map.put("visual_language", visual_language)
  end

  def add_composite_bldg_metadata(%{"entity_type" => entity_type} = entity) do
    case Map.get(@default_visual_language, entity_type) do
      %{"flr_height" => flr_height, "flr0_height" => flr0_height} ->
        data = %{flr_height: flr_height, flr0_height: flr0_height}
        {_, data_json} = JSON.encode(data)

        visual_language = Map.get(entity, "visual_language") || @default_visual_language

        entity
        |> Map.put("is_composite", true)
        |> Map.put("data", data_json)
        |> Map.put("visual_language", visual_language)

      _ ->
        case Map.get(entity, "is_composite") do
          nil -> Map.put(entity, "is_composite", false)
          _ -> entity
        end
    end
  end

  def add_composite_bldg_metadata(entity) do
    case Map.get(entity, "is_composite") do
      nil -> Map.put(entity, "is_composite", false)
      _ -> entity
    end
  end

  def remove_build_params(entity) do
    Map.delete(entity, "container_web_url")
  end

  @doc """
    Receives data for some entity, e.g.:
    "entity": {
      "container_web_url": "https://fromteal.app",
      "web_url": "https://dibau.wordpress.com/",
      "name": "Udi h Bauman",
      "entity_type": "member",
      "state": "approved",
      "summary": "Playing computer programming in the fromTeal band",
      "picture_url": "https://d1qb2nb5cznatu.cloudfront.net/users/9798944-original?1574104158"
    }
    Creates a building matching the entity, e.g.:
    "bldg": {
      "address": "g/b(17,24)/l0/b(55,135)",
      "flr": "g/b(17,24)/l0",
      "x": 55,
      "y": 135,
      "is_composite": false,
      "web_url": "https://dibau.wordpress.com/",
      "name": "Udi h Bauman",
      "entity_type": "member",
      "state": "approved",
      "summary": "Playing computer programming in the fromTeal band",
      "picture_url": "https://d1qb2nb5cznatu.cloudfront.net/users/9798944-original?1574104158"
    }
  """
  def build(entity) do
    entity
    |> figure_out_flr()
    |> figure_out_bldg_url()
    |> decide_on_location()
    |> calculate_nesting_depth()
    |> add_composite_bldg_metadata()
    |> remove_build_params()
  end

  # TODO duplicate code, please consolidate
  def append_message_to_list(msg_list, msg) do
    case msg_list do
      nil -> [msg]
      _ -> [msg | msg_list]
    end
  end

  # TODO duplicate code, please consolidate
  def is_command(msg_text), do: String.at(msg_text, 0) == "/"

  # TODO duplicate code, please consolidate
  def say(%Bldg{} = bldg, msg) do
    {_, text} =
      msg
      |> Map.merge(%{"say_time" => System.system_time(:millisecond)})
      |> JSON.encode()

    prev_messages = Utils.limit_list_to(bldg.previous_messages, 10)
    IO.puts("~~~~~ reduced list size to: #{Enum.count(prev_messages)}")

    new_prev_messages = append_message_to_list(prev_messages, text)
    changes = %{previous_messages: new_prev_messages}
    result = update_bldg(bldg, changes)

    # the message may be a command for bldg manipulation, so
    # broadcast an event for it, so that the command executor can process it
    if is_command(msg["say_text"]) do
      BldgServerWeb.Endpoint.broadcast!(
        "chat",
        "new_message",
        msg
      )
    end

    result
  end

  def get_batteries_in_floor(flr_url) do
    q =
      from(b in Bldg,
        where: b.flr_url == ^flr_url and b.entity_type == "battery"
      )

    Repo.all(q)
  end

  def extract_battery_type(%{entity_type: "battery", name: name}) do
    name
  end
end
