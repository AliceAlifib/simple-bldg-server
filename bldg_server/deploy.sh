#!/bin/bash
# Deploy bldg-server to Fly.io. Selects env config and app based on arg.
#
# Usage (run from inside bldg_server/):
#   ./deploy.sh dev    # deploys to bldg-server       (personal org)
#   ./deploy.sh prod   # deploys to bldg-server-prod  (alice-in org)
#
# Extra args forward to fly deploy, e.g.: ./deploy.sh prod --ha=false
#
# After a first prod deploy on a fresh DB, remember to seed the root bldg:
#   fly ssh console -a bldg-server-prod -C '/app/bin/bldg_server eval "BldgServer.Release.seed_ground()"'

set -e

ENV="${1:-}"
shift || true

case "$ENV" in
  dev)
    CONFIG="fly.dev.toml"
    APP="bldg-server"
    ;;
  prod)
    CONFIG="fly.prod.toml"
    APP="bldg-server-prod"
    ;;
  *)
    echo "Usage: $0 <dev|prod> [extra fly deploy flags]" >&2
    exit 1
    ;;
esac

echo "Deploying to $APP using $CONFIG..."
fly deploy -c "$CONFIG" -a "$APP" "$@"

echo "Done."
