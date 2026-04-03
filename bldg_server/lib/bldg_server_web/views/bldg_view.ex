defmodule BldgServerWeb.BldgView do
  use BldgServerWeb, :view
  alias BldgServerWeb.BldgView

  def render("index.json", %{bldgs: bldgs}) do
    %{data: render_many(bldgs, BldgView, "bldg.json")}
  end

  def render("show.json", %{bldg: bldg}) do
    %{data: render_one(bldg, BldgView, "bldg.json")}
  end

  def render("look.json", %{bldgs: bldgs}) do
    render_many(bldgs, BldgView, "bldg.json")
  end

  def render("bldg.json", %{bldg: bldg}) do
    %{id: bldg.id,
      bldg_url: bldg.bldg_url,
      address: bldg.address,
      name: bldg.name,
      flr: bldg.flr,
      flr_url: bldg.flr_url,
      flr_level: bldg.flr_level,
      nesting_depth: bldg.nesting_depth,
      x: bldg.x,
      y: bldg.y,
      is_composite: bldg.is_composite,
      web_url: bldg.web_url,
      entity_type: bldg.entity_type,
      state: bldg.state,
      category: bldg.category,
      tags: bldg.tags,
      summary: bldg.summary,
      picture_url: bldg.picture_url,
      owners: bldg.owners,
      previous_messages: bldg.previous_messages,
      updated_at: bldg.updated_at,
      data: bldg.data,
      visual_language: if(bldg.visual_language, do: Jason.encode!(bldg.visual_language), else: nil)}
  end
end
