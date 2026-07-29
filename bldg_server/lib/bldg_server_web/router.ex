defmodule BldgServerWeb.Router do
  use BldgServerWeb, :router

  import BldgServerWeb.ResidentAuth,
    only: [
      fetch_current_resident: 2,
      require_authenticated_resident: 2,
      fetch_current_service: 2,
      require_authenticated_service: 2
    ]

  import BldgServerWeb.BatteryAuth,
    only: [
      fetch_current_battery: 2,
      require_authenticated_battery: 2,
      require_battery_provisioning: 2
    ]

  # Base: parse JSON and resolve the bearer token into :current_resident (or the
  # trusted service into :current_service).
  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_current_resident)
    plug(:fetch_current_service)
  end

  # Trusted first-party service (alice-in-goals). Always enforced.
  pipeline :require_service do
    plug(:require_authenticated_service)
  end

  # Resident-authenticated routes (reads and mutations). In dual-run the require
  # plug logs but does not reject; flip :enforce_auth to enforce.
  pipeline :require_resident do
    plug(:require_authenticated_resident)
  end

  # Battery (machine) routes: resolve + require a service key.
  pipeline :battery do
    plug(:fetch_current_battery)
    plug(:require_authenticated_battery)
  end

  # Battery credential provisioning (register): gated by the out-of-band token.
  pipeline :battery_provisioning do
    plug(:require_battery_provisioning)
  end

  # --- Public: login + verification (no credential yet) ---------------------
  scope "/v1", BldgServerWeb do
    pipe_through(:api)

    post("/residents/login", ResidentController, :login)
    get("/residents/verify", ResidentController, :verify_email)
    get("/residents/verification_status", ResidentController, :verification_status)
  end

  # --- Resident-authenticated (reads require auth too) ----------------------
  scope "/v1", BldgServerWeb do
    pipe_through([:api, :require_resident])

    get("/bldgs/resolve_address", BldgController, :resolve_address)
    get("/bldgs/by_bldg_url", BldgController, :show_by_bldg_url)
    get("/bldgs/look/:flr", BldgController, :look)
    get("/bldgs/scan/:flr", BldgController, :scan)
    post("/bldgs/build", BldgController, :build)
    post("/bldgs/:address/relocate_to/:new_address", BldgController, :relocate)
    post("/bldgs/:address/favorite_view_points", BldgController, :add_favorite_view_point)

    get("/residents/look/:flr", ResidentController, :look)
    get("/residents/scan/:flr", ResidentController, :scan)
    post("/residents/act", ResidentController, :act)

    get("/roads/look/:flr", RoadController, :look)
    get("/roads/scan/:flr", RoadController, :scan)

    resources("/bldgs", BldgController, except: [:new, :edit], param: "address")
    resources("/residents", ResidentController, except: [:new, :edit])
    resources("/roads", RoadController, except: [:new, :edit])
  end

  # --- Trusted service (alice-in-goals) -------------------------------------
  scope "/v1", BldgServerWeb do
    pipe_through([:api, :require_service])

    # Mint a resident bearer token for the embedded web client. The service
    # vouches that the resident is authenticated on its side (Google OAuth).
    post("/residents/:id/token", ResidentController, :mint_token)
  end

  # --- Battery credential provisioning --------------------------------------
  scope "/v1", BldgServerWeb do
    pipe_through([:api, :battery_provisioning])

    post("/batteries/register", BatteryController, :register)
  end

  # --- Battery-authenticated (machine callers) ------------------------------
  scope "/v1", BldgServerWeb do
    pipe_through([:api, :battery])

    post("/batteries/unregister", BatteryController, :unregister)
    post("/batteries/attach", BatteryController, :attach)
    post("/batteries/detach", BatteryController, :detach)
    post("/batteries/act", BldgController, :act)

    # Bulk floor deletes are driven by the file-system-battery's re-render flow.
    post("/roads/delete_in_flr", RoadController, :delete_in_flr)
    post("/bldgs/delete_in_flr", BldgController, :delete_in_flr)

    get("/staging/data/:namespace/:entity_type", StagingController, :read_by_type)
    get("/staging/data/:namespace", StagingController, :read_by_namespace)
    post("/staging/query", StagingController, :run_query)
    post("/staging/data", StagingController, :write_data)

    resources("/batteries", BatteryController,
      except: [:new, :edit, :create],
      param: "bldg_address"
    )
  end
end
