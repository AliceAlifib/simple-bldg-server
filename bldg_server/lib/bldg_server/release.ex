defmodule BldgServer.Release do
    @app :bldg_server
  
    def migrate do
      Application.ensure_all_started(@app)
      for repo <- repos() do
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      end
    end

    def rollback(repo, version) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    end

    @doc """
    Idempotently inserts the root "ground" bldg (`address = "g"`). The ground
    bldg also serves as the org container — alice-in-goals sets
    `container_web_url` to a URL like "https://alicein.app", and the lookup
    must resolve to the ground bldg's web_url. Run once per fresh env:

        # prod:
        fly ssh console -a bldg-server-prod -C \\
          '/app/bin/bldg_server eval "BldgServer.Release.seed_ground(\\"https://alicein.app\\", \\"G\\")"'

        # dev (matches existing dev DB):
        fly ssh console -a bldg-server -C \\
          '/app/bin/bldg_server eval "BldgServer.Release.seed_ground(\\"https://alicein.co\\", \\"G\\")"'
    """
    # Canonical set of battery bldgs seeded on the ground, mirroring dev's
    # catalog. Coordinates match dev's placement so the visual layout of the
    # ground floor is consistent across envs. Modify this list if prod should
    # offer a different set of batteries.
    @seed_batteries [
      %{bldg_url: "g/alicein-jira-battery",   name: "alicein-jira-battery",  summary: "Jira-connector",          x: 17, y: -13},
      %{bldg_url: "g/setup-battery",          name: "setup-battery",         summary: "Setup Battery",           x: 14, y:  11},
      %{bldg_url: "g/titanic-battery",        name: "titanic-battery",       summary: "Titanic Dataset Battery", x: 11, y: -13},
      %{bldg_url: "g/alicein-trello-battery", name: "trello-connector",      summary: "Trello-connector",        x: 13, y: -13},
      %{bldg_url: "g/alicein-eng-battery",    name: "alicein-eng-assistant", summary: "Fishbone-organizer",      x: 15, y: -13},
      %{bldg_url: "g/alicein-mcp-battery",    name: "alice-in-mcp-battery",  summary: "Alicein-MCP-Battery",     x: 19, y: -13}
    ]

    @doc """
    Idempotently inserts all catalog battery bldgs at the ground level. Run
    once per fresh env, after seed_ground:

        fly ssh console -a bldg-server-prod -C \\
          '/app/bin/bldg_server eval "BldgServer.Release.seed_batteries()"'

    Safe to re-run — existing entries are detected by bldg_url and skipped.
    """
    def seed_batteries do
      Application.ensure_all_started(@app)

      for battery <- @seed_batteries do
        seed_battery(battery)
      end

      :ok
    end

    @doc """
    Inserts a single battery bldg at the ground level. See seed_batteries/0
    for the canonical list. Pass a map with :bldg_url, :name, :summary, :x, :y.
    """
    def seed_battery(%{bldg_url: bldg_url, name: name, summary: summary, x: x, y: y}) do
      Application.ensure_all_started(@app)

      alias BldgServer.Buildings
      alias BldgServer.Buildings.Bldg
      alias BldgServer.Repo

      case Buildings.get_by_bldg_url(bldg_url) do
        nil ->
          attrs = %{
            "address" => "g/b(#{x},#{y})",
            "bldg_url" => bldg_url,
            "web_url" => "",
            "flr" => "g",
            "flr_url" => "g",
            "flr_level" => 0,
            "nesting_depth" => 0,
            "x" => x,
            "y" => y,
            "is_composite" => false,
            "name" => name,
            "summary" => summary,
            "entity_type" => "battery",
            "state" => "approved",
            "owners" => []
          }

          case %Bldg{} |> Bldg.changeset(attrs) |> Repo.insert() do
            {:ok, bldg} ->
              IO.puts("Seeded battery #{bldg_url} at (#{x},#{y})")
              {:ok, bldg}

            {:error, err} ->
              IO.puts("Failed to seed battery #{bldg_url}: #{inspect(err)}")
              {:error, err}
          end

        %Bldg{} = existing ->
          IO.puts("Battery #{bldg_url} already exists — skipping")
          {:ok, existing}
      end
    end

    def seed_ground(web_url, name \\ "G", summary \\ "Ground level") do
      Application.ensure_all_started(@app)

      alias BldgServer.Buildings
      alias BldgServer.Buildings.Bldg
      alias BldgServer.Repo

      case Buildings.get_by_bldg_url("g") do
        nil ->
          attrs =
            %{
              "address" => "g",
              "bldg_url" => "g",
              "web_url" => web_url,
              # flr/flr_url MUST be "" (not "g") for the ground itself —
              # notify_bldg_created uses these to walk up to the parent
              # container. If flr = "g", the recursion looks up "g" again,
              # finds itself, and loops forever. Empty terminates the walk.
              "flr" => "",
              "flr_url" => "",
              "flr_level" => 0,
              "nesting_depth" => 0,
              "x" => 0,
              "y" => 0,
              "is_composite" => true,
              "name" => name,
              "summary" => summary,
              "entity_type" => "ground",
              # owners must be [] (not nil) — otherwise notify_bldg_created
              # crashes on List.first(nil) when a child bldg's creation
              # propagates a notification up to this ground container.
              "owners" => [],
              "visual_language" => Buildings.default_visual_language()
            }
            |> Buildings.add_composite_bldg_metadata()

          {:ok, bldg} =
            %Bldg{}
            |> Bldg.changeset(attrs)
            |> Repo.insert()

          IO.puts("Seeded ground bldg with web_url #{web_url}: #{inspect(bldg.bldg_url)}")
          {:ok, bldg}

        %Bldg{} = existing ->
          IO.puts("Ground bldg already exists (web_url=#{existing.web_url}) — skipping")
          {:ok, existing}
      end
    end
  
    defp repos do
      Application.load(@app)
      Application.fetch_env!(@app, :ecto_repos)
    end
  end
  