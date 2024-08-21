defmodule BldgServerWeb.ResidentView do
  use BldgServerWeb, :view
  alias BldgServerWeb.ResidentView

  def render("index.json", %{residents: residents}) do
    %{data: render_many(residents, ResidentView, "resident.json")}
  end

  def render("show.json", %{resident: resident}) do
    %{data: render_one(resident, ResidentView, "resident.json")}
  end

  def render("look.json", %{residents: residents}) do
    render_many(residents, ResidentView, "resident.json")
  end

  def render("resident.json", %{resident: resident}) do
    %{id: resident.id,
      email: resident.email,
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
      session_id: resident.session_id,
      last_login_at: resident.last_login_at,
      updated_at: resident.updated_at
    }
  end
end
