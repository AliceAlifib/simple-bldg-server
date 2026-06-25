# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# On a deployed Fly app, run as:
#
#     fly ssh console -a bldg-server-prod -C '/app/bin/bldg_server eval "Code.require_file(\"/app/lib/bldg_server-0.9.0/priv/repo/seeds.exs\")"'
#
# (the release keeps priv/ next to the beam files — path may need adjusting
# by release version; alternatively run the eval with the module body inline)

alias BldgServer.Buildings
alias BldgServer.Buildings.Bldg
alias BldgServer.Repo

# Insert the root "ground" bldg if missing. Every hierarchical address in this
# app lives under "g" — without it, the first bldg creation fails with a
# KeyError in figure_out_flr because the container lookup returns nil.
case Buildings.get_by_bldg_url("g") do
  nil ->
    ground_attrs = %{
      "address" => "g",
      "bldg_url" => "g",
      "web_url" => "g",
      "flr" => "g",
      "flr_url" => "g",
      "flr_level" => 0,
      "nesting_depth" => 0,
      "x" => 0,
      "y" => 0,
      "is_composite" => true,
      "name" => "ground",
      "entity_type" => "ground",
      "visual_language" => Buildings.default_visual_language()
    }

    # Apply the same composite metadata (flr_height, visual_language, data)
    # that Buildings.create_bldg/1 would apply, so later API calls see a
    # consistent shape.
    attrs = Buildings.add_composite_bldg_metadata(ground_attrs)

    {:ok, bldg} =
      %Bldg{}
      |> Bldg.changeset(attrs)
      |> Repo.insert()

    IO.puts("Seeded ground bldg: #{inspect(bldg.bldg_url)}")

  %Bldg{} = existing ->
    IO.puts("Ground bldg already exists: #{inspect(existing.bldg_url)} — skipping")
end
