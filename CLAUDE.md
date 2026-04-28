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
- **BatteryChatDispatcher** (`lib/bldg_server_web/battery_chat_dispatcher.ex`) — Forwards chat messages to attached batteries' webhook endpoints.
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

### Visual Language

The `visual_language` field (map) on container bldgs decouples `entity_type` from 3D rendering. `Buildings.default_visual_language/0` defines 50+ entity-type-to-3D-object mappings (e.g., `"team"` → `"buildingWithStorefront"`). Containers set this on their floors; child bldgs inherit the mapping to determine their visual representation.

### DGraph Staging

The staging API uses DGraph with DQL queries. The `namespace` concept is stored as `ns` in the DGraph schema (renamed to avoid conflict with DGraph's internal `namespace` keyword). Staging data is organized by `ns` and `entity_type`.

## Key Conventions

- JSON API only (no HTML views) — all controllers render JSON via view modules in `views/`.
- Auto-placement logic in `Buildings.create_bldg/1` handles coordinate collision by shifting x+1 and retrying.
- Composite entity types (e.g., "team", "project") have predefined floor heights in `BldgController`.
- Building creation triggers hierarchical notifications up the container chain.
- GenServers (`BldgCommandExecutor`, `BatteryChatDispatcher`) subscribe to Phoenix PubSub "chat" topic — commands are broadcast, not called directly.
- `Buildings.delete_bldg_cascade/1` deletes nested descendants deepest-first plus their roads before the target; residents inside deleted bldgs are left untouched. `DELETE /v1/bldgs/:address` and the `/delete bldg {name}` chat command both route through it (authorized via `is_authorized_owner?/2`).
- Roads cache `from_address`/`to_address` and endpoint coordinates at creation. `Buildings.update_bldg/2` diffs the `address` on update and, on change, calls `Relations.cascade_bldg_relocation/3` to rewrite matching endpoints (following the flr when the road lived on the bldg's prior floor) and re-broadcast `road_updated`. Skipping this leaves roads visually dangling at the old position.
