defmodule BldgServerWeb.FloorChannel do
  use Phoenix.Channel

  alias BldgServer.Buildings
  alias BldgServer.Residents
  alias BldgServer.Relations

  require Logger

  def join("floor:" <> flr, _params, socket) do
    # Require an authenticated principal to join (any resident, or a machine
    # principal like a battery). Dual-run: when :enforce_auth is off, anonymous
    # joins are allowed.
    if socket.assigns[:current_resident] || socket.assigns[:machine_authed] ||
         not BldgServerWeb.ResidentAuth.enforce_auth?() do
      Logger.info("[FloorChannel] Client joined floor:#{flr}")
      {:ok, assign(socket, :flr, flr)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("request_scan", _params, socket) do
    flr = socket.assigns.flr

    container_bldg_addr = Buildings.get_flr_bldg(flr)
    container = Buildings.get_bldg!(container_bldg_addr)
    bldgs = Buildings.list_all_bldgs_in_flr(flr)
    residents = Residents.list_all_residents_in_flr(flr)
    roads = Relations.list_all_roads_in_flr(flr)

    push(socket, "scan_result", %{
      bldgs: Enum.map([container | bldgs], &serialize_bldg/1),
      residents: Enum.map(residents, &serialize_resident_public/1),
      roads: Enum.map(roads, &serialize_road/1)
    })

    {:noreply, socket}
  end

  # Serialization helpers -- same shape as the view render functions

  def serialize_bldg(bldg) do
    %{
      id: bldg.id,
      bldg_url: bldg.bldg_url,
      address: bldg.address,
      name: bldg.name,
      flr: bldg.flr,
      flr_url: bldg.flr_url,
      flr_level: bldg.flr_level,
      nesting_depth: bldg.nesting_depth,
      x: bldg.x,
      y: bldg.y,
      width: bldg.width,
      height: bldg.height,
      is_composite: bldg.is_composite,
      web_url: bldg.web_url,
      entity_type: bldg.entity_type,
      state: bldg.state,
      category: bldg.category,
      tags: bldg.tags,
      summary: bldg.summary,
      picture_url: bldg.picture_url,
      color: bldg.color,
      size: bldg.size,
      variant: bldg.variant,
      owners: bldg.owners,
      previous_messages: bldg.previous_messages,
      updated_at: bldg.updated_at,
      data: bldg.data,
      visual_language:
        if(bldg.visual_language, do: Jason.encode!(bldg.visual_language), else: nil),
      # Keep parity with BldgView.render("bldg.json"): a channel scan must carry
      # favorite_view_points too, or clients hydrating from the channel lose them.
      favorite_view_points: bldg.favorite_view_points || []
    }
  end

  # Public resident shape broadcast over the floor channel to every joiner.
  # DELIBERATELY omits `email` and `session_id`: the channel is world-readable
  # (any socket can join a floor), and session_id is a credential used by the
  # verification_status flow — neither may leak to other clients. Full detail
  # (incl. email) is served only to the resident themselves via the
  # authenticated REST endpoint.
  def serialize_resident_public(resident) do
    %{
      id: resident.id,
      alias: resident.alias,
      name: resident.name,
      home_bldg: resident.home_bldg,
      is_online: resident.is_online,
      location: resident.location,
      flr: resident.flr,
      flr_url: resident.flr_url,
      x: resident.x,
      y: resident.y,
      direction: resident.direction,
      previous_messages: resident.previous_messages,
      other_attributes: resident.other_attributes,
      nesting_depth: resident.nesting_depth,
      last_login_at: resident.last_login_at,
      updated_at: resident.updated_at,
      view_mode: resident.view_mode
    }
  end

  def serialize_road(road) do
    %{
      id: road.id,
      flr: road.flr,
      from_address: road.from_address,
      to_address: road.to_address,
      from_x: road.from_x,
      from_y: road.from_y,
      to_x: road.to_x,
      to_y: road.to_y,
      owners: road.owners,
      color: road.color,
      road_class: road.road_class,
      curve: road.curve
    }
  end
end
