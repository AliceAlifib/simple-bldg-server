# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BldgServer is a reference implementation of the Alice-in protocol server, built with Elixir/Phoenix 1.7. It serves Alice-in visualizations to clients and manages hierarchical data entities ("buildings"), relationships ("roads"), users ("residents"), and external integrations ("batteries").

## Build & Development Commands

All commands run from the `bldg_server/` directory:

```bash
mix deps.get              # Install dependencies
mix ecto.setup            # Create DB, run migrations, seed
mix ecto.migrate          # Run pending migrations
mix ecto.reset            # Drop DB, recreate, migrate, seed
mix phx.server            # Start dev server (HTTP :4000, HTTPS :4443)
mix test                  # Run all tests
mix test test/path_test.exs          # Run a single test file
mix test test/path_test.exs:42       # Run a specific test by line
mix coveralls             # Run tests with coverage (ExCoveralls)
mix format                # Format (config in .formatter.exs; imports ecto + phoenix)
```

The `mix test` alias auto-runs `ecto.create` and `ecto.migrate` before tests (test DB: `bldg_server_test`).

Docker for local dev (starts PostgreSQL):
```bash
docker-compose up
```

`application.ex` reads `REDIS_HOST`, `REDIS_PWD`, `REDIS_PORT` via `System.fetch_env!` at boot, so **dev hard-crashes without them**; `config/runtime.exs` injects localhost/6379/blank defaults for `MIX_ENV=test` only. A blank `REDIS_PWD` is treated as "no auth" (no `AUTH ""` sent), so a stock password-less local Redis works. DB config reads `DB_USER`, `DB_PASSWORD`, `DB_HOST` with defaults.

Production release runs migrations via `/app/bin/migrate`.

## Architecture

### Domain Model

- **Bldg** (`lib/bldg_server/buildings.ex`, schema in `buildings/bldg.ex`) — Core entity. Represents anything: buildings, members, teams, stages, milestones. Has a hierarchical address system rooted at "g" (ground), e.g. `g/b(3,2)/l0/b(1,1)`.
- **Resident** (`lib/bldg_server/residents.ex`) — User accounts with email-based passwordless auth (magic link verification).
- **Battery** (`lib/bldg_server/batteries.ex`) — External data source integrations that attach to buildings and sync data.
- **Road** (`lib/bldg_server/relations.ex`) — Relationships/connections between buildings.
- **Marker** (`lib/bldg_server/relations.ex`, schema in `relations/marker.ex`) — Floor-level geometric idiom that, unlike a road, isn't anchored to bldgs: `marker_type` `path` (polyline, ≥2 points) or `area` (closed polygon, ≥3 points) through floor-local cells (`xs`/`ys` pairwise integer arrays), with optional `color`, `marker_class` (`highway|road|lane|path`, default `road`), `owners`, `data`. Identity is `(flr, name)` (unique index) so `Relations.upsert_marker/1` is idempotent — an unchanged re-emit is a no-op (no write/broadcast), a changed one updates in place (same id). Swept by `delete_bldg_cascade/1` and `flr`-rebased by `relocate_bldg_cascade/3` like roads; broadcasts `marker_created/updated/deleted` and rides `scan_result.markers` on the floor channel.

### Key Subsystems

- **BldgCommandExecutor** (`lib/bldg_server_web/bldg_command_executor.ex`) — Processes chat commands ("say" actions) in buildings, broadcasts via Phoenix PubSub on the "chat" topic.
- **BatteryChatDispatcher** (`lib/bldg_server_web/battery_chat_dispatcher.ex`) — Forwards chat messages to batteries' webhook endpoints (attached batteries directly, others via a registered Redis pool; see Battery Dispatch).
- **DgraphClient** (`lib/bldg_server/dgraph_client.ex`) — Client for the DGraph graph database, used for staging/transient data.
- **StagingController** — Manages temporary/staged data in the graph DB with namespace/entity_type organization.
- **Notifications** (`lib/bldg_server/notifications.ex`) — Propagates creation/update events up the container hierarchy.
- **FloorChannel** (`lib/bldg_server_web/channels/floor_channel.ex`) — Phoenix Channel on `floor:*` topics that streams real-time `bldg_created/updated/deleted`, `resident_*`, and `road_*` events to clients (replaces HTTP polling). Mutations in `Buildings`/`Residents`/`Relations` broadcast to the target floor **and every ancestor floor**, so clients doing recursive `scan` receive nested changes.

### Chat Commands

`POST /v1/residents/act` with `action_type: "SAY"` → `Residents.say/2` persists the message and, if `is_command/1` (text starts with `/`), fire-and-forget-broadcasts it on the "chat" PubSub topic. `BldgCommandExecutor.handle_info/2` splits `say_text` on spaces and pattern-matches the token list in `execute_command/2`. The grammar (one clause per shape):

```
/create {entity_type} bldg with {k} {v} and {k} {v} ...   # name, summary, x/y, width/height, ...
/connect between {name1} and {name2} [with color X and class Y and curve Z]
/mark path|area with name {name} and points (x,y) (x,y) ... [and color X] [and class Y]   # kwargs any order; upserts by (flr, name)
/edit {name} {field} {value...}        # @editable_fields: state summary category picture_url web_url data tags color size variant
/delete bldg {name}
/add owner {email} to bldg {name}   |  /remove owner {email} from bldg {name}
/move bldg {name} here     |  /relocate bldg {bldg_url} here
/promote bldg {name} inside  |  /demote bldg {name} inside
```

Conventions that bite when adding a command:
- **The message map has string keys** (it comes from the JSON body and is broadcast verbatim). Clauses must destructure `%{"say_location" => ...}`, not atom keys — an atom-key pattern silently never matches and falls through to the next clause. (`/move bldg ... here` at `bldg_command_executor.ex:419` currently has this defect and always hits its own "missing parameters" error clause.)
- Every command ends in a *terminal* keyword (`here`, `inside`, `bldg {name}`) because parsing is positional token matching, not a real parser. Each real clause is paired with a fallback clause that raises a descriptive "missing required say fields" error.
- Execution is **async** — the HTTP caller already got a 200. `handle_info` wraps execution in `try/rescue` so an `Unauthorized` raise or a missing bldg doesn't crash the GenServer and drop its "chat" subscription; failures only show up as `Logger.error`. This is why `create_bldg` logs insert failures loudly.
- Authorization inside commands is `Buildings.is_authorized_owner?/2` + `raise "Unauthorized"` — not the `ResidentAuth` plugs (which only guard the HTTP layer).

### Address System

The hierarchical address is central to the data model:
- Root floor: `"g"` (ground)
- Building addresses: `g/b(x,y)` where x,y are coordinates
- Nested floors: `g/b(x,y)/l0/b(x,y)` — buildings contain floors which contain more buildings
- Delimiter: `"/"`
- Each bldg has: `address`, `flr` (parent floor), `flr_url`, `entity_type`, `x`, `y`

Parsing is centralized in **`BldgServer.Address`** (`lib/bldg_server/address.ex`) — a *total* parser that turns a path into typed segments (`:ground`, `{:bldg, x, y}`, `{:floor, n}`, or `{:named, s}`), with `to_string/1` round-tripping. The scattered string-slicing primitives (`extract_coords`, `get_container`, `extract_flr_level`, `calculate_nesting_depth`) delegate to it; it also provides `ancestor?/2` (structural, not text-prefix — so `l1` is not an ancestor of `l10`) and `rebase/3` (re-root a subtree). **Dual hierarchy:** an `address` uses coordinate `b(x,y)` bldg-segments, while a `bldg_url` uses **name** segments (built as `flr_url/name`, e.g. `g/team/l0/task1`); both alternate with `l<n>` floor segments, which is why `{:named, s}` exists and why relocation rebases the two on different roots.

### Data Stores

- **PostgreSQL** — Primary database (Ecto/postgrex)
- **Redis** (Upstash in prod) — Caching and pub/sub via Redix
- **DGraph** — Graph database for staging/transient data queries
- **Finch** (`FinchClient`) — HTTP client for outbound requests (battery webhooks, DGraph API)

### API Structure

All API routes are under `/v1/` (see `lib/bldg_server_web/router.ex`):
- `/bldgs/*` — Building CRUD, lookup by address/url, `look`/`scan` for listing, `relocate_to`, `favorite_view_points`, `delete_in_flr` (bulk)
- `/residents/*` — Auth (login/verify), resident actions, `look`/`scan`
- `/roads/*` — Relationship management, `look`/`scan`, `delete_in_flr` (bulk)
- `/markers/*` — Marker CRUD, `look`/`scan`, `delete_in_flr` (bulk) — same shape as roads
- `/batteries/*` — Register/unregister, attach/detach, act
- `/staging/*` — Read/write/query staged data by namespace

`look/:flr` returns direct children of a floor; `scan/:flr` returns all nested descendants. The `delete_in_flr` endpoints bulk-delete every road/bldg in a floor subtree (used by batteries' clear-and-repopulate re-render flow); they delete by struct and rescue `StaleEntryError` so duplicate or already-cascaded rows don't abort the sweep.

Bldgs carry a `favorite_view_points` array of named camera poses (`address`, `direction`, `size_delta`, `camera_vertical_angle`); appended via `POST /v1/bldgs/:address/favorite_view_points`.

## Testing

The suite needs **both PostgreSQL and a running local Redis** — `bldg_command_executor_more_test.exs` issues real `Redix.command(:redix, ...)` calls against `localhost:6379`, so a missing Redis fails those tests rather than skipping them.

- **`BldgServer.Factory`** (`test/support/factory.ex`, auto-imported by `DataCase`/`ConnCase`/`ChannelCase`) builds records **directly via `Repo`**, deliberately bypassing the notify/broadcast side effects in the context `create_*` functions. Use it for cheap setup; call the context function itself when the test is exercising that create path. Coords/emails default to unique values to dodge `unique_constraint` collisions.
- **`Factory.seed_ground_floor/0` is required** before any test that calls `Buildings.create_bldg/1` for a bldg rooted on `g` — `notify_bldg_created/4` looks up the container floor and blows up if `g` is absent.
- **External HTTP boundaries are faked with a throwaway `Plug.Cowboy` server**, not Bypass (see the comment in `mix.exs`: Bypass pins ranch ~> 1.3, which conflicts with the ranch 2.x cowboy 2.14 requires). The pattern — a tiny `Catcher`/`FakeDgraph` plug started on a fixed port with `test_pid: self()`, torn down in `on_exit`, asserting on forwarded messages — lives in `battery_dispatch_test.exs`, `battery_chat_dispatcher_test.exs`, and `staging_controller_test.exs`. `:dgraph_url` is repointed at the fake via `Application.put_env`.
- **Outbound mail** uses `Bamboo.TestAdapter` in test config, so assert with `Bamboo.Test`'s `assert_delivered_email/1`. `runtime.exs` explicitly skips the SendGrid adapter block in test — it runs *after* compile-time config and would otherwise clobber it, making login tests hit the real SendGrid.
- **Auth-enforcement tests flip the flag at runtime**: `Application.put_env(:bldg_server, :enforce_auth, true)` with the previous value restored in `on_exit` (see `resident_auth_test.exs`). Since the default is `false`, a test asserting a 401/403 must set it explicitly.
- Tests default to the **shared** SQL sandbox (`ConnCase`/`DataCase` set `{:shared, self()}` unless `async: true`), which is what lets GenServer-driven code (command executor, dispatcher) see test data.

## Deployment

Deployed to Fly.io via split dev/prod stacks (`bldg_server/fly.dev.toml`, `bldg_server/fly.prod.toml`), primary region SJC. GitHub Actions: `deploy.yml` auto-deploys master to the dev stack on push, while prod deploys are manual (`workflow_dispatch` with target `prod`). **`elixir.yml` is broken and has failed on every run for months** — it runs from the repo root (no `mix.exs` there; the project lives in `bldg_server/`), pins Elixir 1.10.3 / OTP 22.3 against a codebase built on 1.16.2 / OTP 26.2.2, and provisions no Postgres or Redis service containers. Treat CI as *not* covering tests: run `mix test` locally before pushing. Multi-stage Dockerfile using Elixir 1.16.2 / OTP 26.2.2. Key env vars configured via Fly secrets: `DB_*`, `REDIS_*`, `DGRAPH_URL`, `SENDGRID_API_KEY`, `SECRET_KEY_BASE`, plus the auth secrets `MAGIC_LINK_SALT`, `AUTH_TOKEN_SALT`, and (optional) `ENFORCE_AUTH`, `BATTERY_PROVISION_TOKEN`, `CORS_ORIGINS`, `BATTERY_URL_ALLOWED_HOSTS`. No secret material lives in source — all signing keys/salts are env-sourced in `config/runtime.exs` (dev/test fall back to clearly non-secret defaults; prod fails loud). Sentry is wired in for error reporting, with a `BldgServer.SentryScrubber` `before_send` hook that redacts PII/credentials.

### Ownership & Authorization

- Bldgs and Roads have an `owners` field (array of email strings).
- `Buildings.is_authorized_owner?/2` checks direct ownership first, then walks up the container hierarchy (via `bldg_url`) to check ancestor ownership — an owner of a parent building can operate on all nested children.
- Floor segments are skipped when walking up, since floors don't have their own bldg entries.
- Used by `BldgCommandExecutor` for `/add owner`, `/remove owner`, `/connect`, `/edit`, and `/delete bldg` commands, and wired into the HTTP controllers via `ResidentAuth.authorize_bldg/2` / `authorize_container/2` for every bldg/road mutation (`create`/`update`/`delete`/`relocate`/`build`/`add_favorite_view_point`). On create, `owners` is bound server-side to the authenticated resident (body-supplied `owners`/`session_id`/`email` are stripped — mass-assignment defense); ownership checks and this binding are gated by `:enforce_auth` (dual-run).

### SSRF & injection guards

- `BldgServer.SafeUrl` validates every battery `callback_url` (in the `Battery` changeset, `register_battery`, and at the dispatch sink) — rejects non-`http(s)` schemes and hosts resolving to loopback/link-local (incl. `169.254.169.254`)/private ranges. Gated by `:block_private_callback_urls` (strict in prod; relaxed in dev/test for loopback), with a `BATTERY_URL_ALLOWED_HOSTS` prod allow-list.
- Staging DQL reads pass the namespace as a bound DQL variable (`$ns`) and validate `entity_type` against a strict identifier regex (no interpolation). Floor-subtree `LIKE` queries escape `%`/`_` in user input via `Utils.escape_like_pattern/1`.

### Authentication Flow

Passwordless email-based auth, then a bearer token for the API/WS:
1. `POST /residents/login` → creates a Session (status: `PENDING-VERIFICATION`) and emails a magic link via SendGrid
2. `GET /residents/verify?token=X` → verifies the magic-link token (24h max age via `Phoenix.Token`), marks session `VERIFIED`
3. The app polls `GET /residents/verification_status` (email + session_id); once `VERIFIED` the response carries a **bearer `token`** (also returned by `login` when a valid session is reused). Sessions track `ip_address`/`last_activity_time`; previous sessions are marked `REPLACED`.
4. The client sends that token as `Authorization: Bearer <token>` on every REST call and as a `token` connect param on the WebSocket. `BldgServer.Token` mints/verifies it (7-day max age, carries `resident_id` + `session_id`); the `sessions` table is the revocation list (a `REPLACED`/missing session rejects the token).

**Auth plugs & pipelines** (`BldgServerWeb.ResidentAuth`, `BldgServerWeb.BatteryAuth`): the router (`router.ex`) splits routes into public (login/verify/verification_status), resident-authenticated (all reads + mutations + `act`), battery-authenticated (register/unregister/attach/detach, `batteries/act`, `staging/*`, `delete_in_flr`), and battery-provisioning (`register`). `fetch_current_resident`/`fetch_current_battery` assign identity; `require_*` reject unauthenticated calls.

**Dual-run rollout**: the `:enforce_auth` app flag (default `false`, overridable via `ENFORCE_AUTH` env) gates all rejection. When `false`, the plugs and `authorize_*` helpers assign identity and log what they *would* block but never reject — so pre-token clients keep working; when `true`, missing/invalid credentials get 401 and ownership failures 403. Flip it once the Unity client and batteries send tokens. **Batteries** (machine callers that can't do magic-link) authenticate with a service API key: `POST /batteries/register` (gated by the `BATTERY_PROVISION_TOKEN`) provisions a key via `Batteries.provision_battery_credential/2` (only the SHA-256 hash is stored, in `battery_credentials`), returned once as `api_key`.

### Resident Action Protocol

`POST /v1/residents/act` is a single endpoint that fans out via pattern-matching on `action_type` in `ResidentController.act/2` (each clause delegates to a `Residents` function): `MOVE`, `TURN`, `SAY`, `ENTER_BLDG`, `ENTER_BLDG_FLR`, `EXIT_BLDG`, and `change_view_mode`. Adding an action means adding a matching `act/2` clause plus its context function; there is no generic dispatcher. State changes persist via `Residents.update_resident/2`, which broadcasts `resident_updated` on the floor channel so other clients reconcile.

`view_mode` (resident field, `bird_eye` | `immersive`, default `bird_eye`, validated by `validate_inclusion`) is a per-user UI preference set through the `change_view_mode` action. Clients hydrate it from the resident payload on login and from `resident_updated` broadcasts. Bird-eye residents have `direction` pinned to `180` — `change_view_mode/2` re-pins it at runtime (not just via the one-time backfill migration).

### Battery Dispatch

`BatteryChatDispatcher` (GenServer subscribed to the "chat" PubSub topic) routes each `new_message` to the battery bldgs on the message's floor (`Buildings.get_batteries_in_floor/1`) via two tiers:

1. **Attached batteries** — a battery bound to one specific bldg (`is_attached: true`, matched by `bldg_url` via `Batteries.get_attached_battery_by_bldg_url/1`, e.g. a per-sprite file-system-battery). The message goes straight to that battery's own `callback_url`.
2. **Registered pool (fallback)** — remaining (non-attached) battery bldgs are deduped by `battery_type` (`Buildings.extract_battery_type/1`), and each type dispatches to a *random* registered `callback_url` looked up from Redis (`Batteries.get_registered_callbacks/1`).

A bldg handled in tier 1 is excluded from tier 2, so attached batteries never also receive the shared type-keyed broadcast.

### Visual Language

The `visual_language` field (map) on container bldgs decouples `entity_type` from 3D rendering. `Buildings.default_visual_language/0` defines 50+ entity-type-to-3D-object mappings (e.g., `"team"` → `"buildingWithStorefront"`). Containers set this on their floors; child bldgs inherit the mapping to determine their visual representation.

Bldgs also carry purely-presentational styling fields decoupled from semantic state: `color` (free-form token, validated against a palette in the client), `size` (T-shirt: XS/S/M/L/XL/XXL), and `variant`. These were historically overloaded onto `state`/`category`; migration `20260505120100` backfills the split. Roads similarly accept optional `color` and `road_class` (`highway|road|lane|path`) fields for styled overlays, plus `curve` (`auto` default | `never`) — `auto` lets the client's planner bend curve-eligible roads around obstacles, `never` pins them straight (e.g. metric lanes intentionally overlaying the fishbone spine).

Stairs bldgs (variant `stairs<N>`) get a `flr_indent` value injected into their composite metadata (`Buildings.maybe_add_stairs_indent/2`) so the client shifts each floor's contents to match the stepped shell prefab; the constant must equal `StairsBldgGeometry.FLR_INDENT` in the bldg-client repo.

### DGraph Staging

The staging API uses DGraph with DQL queries. The `namespace` concept is stored as `ns` in the DGraph schema (renamed to avoid conflict with DGraph's internal `namespace` keyword). Staging data is organized by `ns` and `entity_type`.

## Key Conventions

- JSON API only (no HTML views) — all controllers render JSON via view modules in `views/`.
- Bldgs carry a `width`/`height` footprint (default 1×1; `{x,y}` is the bottom-left origin, covering `x..x+width-1` × `y..y+height-1`). Auto-placement (`Buildings.decide_on_location/1` → `find_free_footprint/5`) scans the floor for the first clear rectangle that doesn't overlap an existing footprint (`footprints_overlap?/2`, `occupied_footprints/1`), falling back to a random slot + the unique-address create-retry when the floor is full. The retry path jitters the bldg's coords (`jitter_bldg_location/1`) on a unique-address constraint violation.
- Composite entity types (e.g., "team", "project") have predefined floor heights in `BldgController`.
- `address`/`bldg_url`/`web_url` are `:text` columns (deep nesting overflows varchar(255)) but are unique-indexed, so `Bldg.changeset` caps them at 2000 chars (Postgres btree entries max ~2704 bytes) to fail with a clear changeset error. Because chat-command execution is async (HTTP caller already got a 200), `create_bldg` logs insert failures loudly — silent insert no-ops previously cost full debug cycles.
- `/connect` is idempotent: `Relations.find_road/3` looks up an existing road by `(flr, from, to)` before creating, so battery re-render passes don't stack duplicates. Optional tail `with color X and class Y and curve Z` (any order/subset). Note roads have a `flr` column, not `flr_url`.
- `/edit ... data ...` validates the value parses as a JSON object before storing — a broken string (e.g. truncated by the chat input length limit) would silently wipe the bldg's rendering attributes on the client.
- Building creation triggers hierarchical notifications up the container chain.
- GenServers (`BldgCommandExecutor`, `BatteryChatDispatcher`) subscribe to Phoenix PubSub "chat" topic — commands are broadcast, not called directly.
- `Buildings.delete_bldg_cascade/1` deletes nested descendants deepest-first plus their roads before the target; residents inside deleted bldgs are left untouched. `DELETE /v1/bldgs/:address` and the `/delete bldg {name}` chat command both route through it (authorized via `is_authorized_owner?/2`).
- Roads cache `from_address`/`to_address` and endpoint coordinates at creation. `Buildings.update_bldg/2` diffs the `address` on update and, on change, calls `Relations.cascade_bldg_relocation/3` to rewrite matching endpoints (following the flr when the road lived on the bldg's prior floor) and re-broadcast `road_updated`. Skipping this leaves roads visually dangling at the old position.
- **Container relocation**: when `update_bldg/2` sees a container's `address` change, `Buildings.relocate_bldg_cascade/3` re-homes the whole nested subtree via `Address.rebase/3` — each descendant bldg's `address`/`flr` is rebased on the new address root and its `bldg_url`/`flr_url` on the new bldg_url root (the two move independently when the container is name-aliased), and roads on descendant floors have their `flr`/endpoints rebased (endpoint coords are floor-local, so preserved). Descendant lookup is delimiter-safe (`list_all_bldgs_in_flr/2` matches `flr == X` or `"X/%"`, never a bare `"X%"` prefix), so sibling subtrees are untouched.

**`/edit data` preserves geometry keys.** `add_composite_bldg_metadata` injects
`flr_height`/`flr0_height`/`flr_indent`/`stairs_indent` into a composite bldg's
`data` at CREATE time, and the client positions the bldg's contents from them.
A battery's `/edit <name> data {...}` (file-system-battery `attach_raw_data`)
would clobber them — `preserve_geometry_data_keys` in the executor merges any
geometry key the new payload doesn't explicitly set (explicit values still win).
