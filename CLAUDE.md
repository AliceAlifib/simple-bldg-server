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
```

The `mix test` alias auto-runs `ecto.create` and `ecto.migrate` before tests (test DB: `bldg_server_test`).

Docker for local dev (starts PostgreSQL):
```bash
docker-compose up
```

The app requires `REDIS_HOST`, `REDIS_PWD`, and `REDIS_PORT` env vars at startup (hard-crashes without them). DB config reads `DB_USER`, `DB_PASSWORD`, `DB_HOST` with defaults.

Production release runs migrations via `/app/bin/migrate`.

## Architecture

### Domain Model

- **Bldg** (`lib/bldg_server/buildings.ex`, schema in `buildings/bldg.ex`) — Core entity. Represents anything: buildings, members, teams, stages, milestones. Has a hierarchical address system rooted at "g" (ground), e.g. `g/b(3,2)/l0/b(1,1)`.
- **Resident** (`lib/bldg_server/residents.ex`) — User accounts with email-based passwordless auth (magic link verification).
- **Battery** (`lib/bldg_server/batteries.ex`) — External data source integrations that attach to buildings and sync data.
- **Road** (`lib/bldg_server/relations.ex`) — Relationships/connections between buildings.

### Key Subsystems

- **BldgCommandExecutor** (`lib/bldg_server_web/bldg_command_executor.ex`) — Processes chat commands ("say" actions) in buildings, broadcasts via Phoenix PubSub on the "chat" topic.
- **BatteryChatDispatcher** (`lib/bldg_server_web/battery_chat_dispatcher.ex`) — Forwards chat messages to batteries' webhook endpoints (attached batteries directly, others via a registered Redis pool; see Battery Dispatch).
- **DgraphClient** (`lib/bldg_server/dgraph_client.ex`) — Client for the DGraph graph database, used for staging/transient data.
- **StagingController** — Manages temporary/staged data in the graph DB with namespace/entity_type organization.
- **Notifications** (`lib/bldg_server/notifications.ex`) — Propagates creation/update events up the container hierarchy.
- **FloorChannel** (`lib/bldg_server_web/channels/floor_channel.ex`) — Phoenix Channel on `floor:*` topics that streams real-time `bldg_created/updated/deleted`, `resident_*`, and `road_*` events to clients (replaces HTTP polling). Mutations in `Buildings`/`Residents`/`Relations` broadcast to the target floor **and every ancestor floor**, so clients doing recursive `scan` receive nested changes.

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
- `/bldgs/*` — Building CRUD, lookup by address/url, `look`/`scan` for listing, `relocate_to`, `favorite_view_points`
- `/residents/*` — Auth (login/verify), resident actions, `look`/`scan`
- `/roads/*` — Relationship management, `look`/`scan`
- `/batteries/*` — Register/unregister, attach/detach, act
- `/staging/*` — Read/write/query staged data by namespace

`look/:flr` returns direct children of a floor; `scan/:flr` returns all nested descendants.

Bldgs carry a `favorite_view_points` array of named camera poses (`address`, `direction`, `size_delta`, `camera_vertical_angle`); appended via `POST /v1/bldgs/:address/favorite_view_points`.

## Deployment

Deployed to Fly.io via split dev/prod stacks (`fly.dev.toml`, `fly.prod.toml` at the repo root), primary region SJC. Multi-stage Dockerfile using Elixir 1.16.2 / OTP 26.2.2. Key env vars configured via Fly secrets: `DB_*`, `REDIS_*`, `DGRAPH_URL`, `SENDGRID_API_KEY`, `SECRET_KEY_BASE`. Sentry is wired in for error reporting (commit `0341b20`).

### Ownership & Authorization

- Bldgs and Roads have an `owners` field (array of email strings).
- `Buildings.is_authorized_owner?/2` checks direct ownership first, then walks up the container hierarchy (via `bldg_url`) to check ancestor ownership — an owner of a parent building can operate on all nested children.
- Floor segments are skipped when walking up, since floors don't have their own bldg entries.
- Used by `BldgCommandExecutor` for `/add owner`, `/remove owner`, `/connect`, `/edit`, and `/delete bldg` commands and by controllers for mutation authorization.

### Authentication Flow

Passwordless email-based auth:
1. `POST /residents/login` → creates a Session (status: `PENDING-VERIFICATION`) and emails a magic link via SendGrid
2. `GET /residents/verify?token=X` → verifies the token (24h max age via `Phoenix.Token`), marks session `VERIFIED`
3. Sessions track `ip_address` and `last_activity_time`; previous sessions are marked `REPLACED`

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

Bldgs also carry purely-presentational styling fields decoupled from semantic state: `color` (free-form token, validated against a palette in the client), `size` (T-shirt: XS/S/M/L/XL/XXL), and `variant`. These were historically overloaded onto `state`/`category`; migration `20260505120100` backfills the split. Roads similarly accept optional `color` and `class` fields for styled overlays.

### DGraph Staging

The staging API uses DGraph with DQL queries. The `namespace` concept is stored as `ns` in the DGraph schema (renamed to avoid conflict with DGraph's internal `namespace` keyword). Staging data is organized by `ns` and `entity_type`.

## Key Conventions

- JSON API only (no HTML views) — all controllers render JSON via view modules in `views/`.
- Bldgs carry a `width`/`height` footprint (default 1×1; `{x,y}` is the bottom-left origin, covering `x..x+width-1` × `y..y+height-1`). Auto-placement (`Buildings.decide_on_location/1` → `find_free_footprint/5`) scans the floor for the first clear rectangle that doesn't overlap an existing footprint (`footprints_overlap?/2`, `occupied_footprints/1`), falling back to a random slot + the unique-address create-retry when the floor is full. The retry path jitters the bldg's coords (`jitter_bldg_location/1`) on a unique-address constraint violation.
- Composite entity types (e.g., "team", "project") have predefined floor heights in `BldgController`.
- Building creation triggers hierarchical notifications up the container chain.
- GenServers (`BldgCommandExecutor`, `BatteryChatDispatcher`) subscribe to Phoenix PubSub "chat" topic — commands are broadcast, not called directly.
- `Buildings.delete_bldg_cascade/1` deletes nested descendants deepest-first plus their roads before the target; residents inside deleted bldgs are left untouched. `DELETE /v1/bldgs/:address` and the `/delete bldg {name}` chat command both route through it (authorized via `is_authorized_owner?/2`).
- Roads cache `from_address`/`to_address` and endpoint coordinates at creation. `Buildings.update_bldg/2` diffs the `address` on update and, on change, calls `Relations.cascade_bldg_relocation/3` to rewrite matching endpoints (following the flr when the road lived on the bldg's prior floor) and re-broadcast `road_updated`. Skipping this leaves roads visually dangling at the old position.
- **Container relocation**: when `update_bldg/2` sees a container's `address` change, `Buildings.relocate_bldg_cascade/3` re-homes the whole nested subtree via `Address.rebase/3` — each descendant bldg's `address`/`flr` is rebased on the new address root and its `bldg_url`/`flr_url` on the new bldg_url root (the two move independently when the container is name-aliased), and roads on descendant floors have their `flr`/endpoints rebased (endpoint coords are floor-local, so preserved). Descendant lookup is delimiter-safe (`list_all_bldgs_in_flr/2` matches `flr == X` or `"X/%"`, never a bare `"X%"` prefix), so sibling subtrees are untouched.
