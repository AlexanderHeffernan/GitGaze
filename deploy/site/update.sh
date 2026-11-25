#!/bin/sh
# Run every minute by gitgaze-site-update.timer: publishes whatever is on main.
set -eu
cd "$(dirname "$0")/../../.."   # ~/gitgaze-site
exec 9>.update.lock
flock -n 9 || exit 0
before=$(git -C repo rev-parse HEAD)
git -C repo fetch -q origin main
git -C repo reset -q --hard origin/main
after=$(git -C repo rev-parse HEAD)
[ "$before" = "$after" ] && exit 0
echo "Published $after"
if ! git -C repo diff --quiet "$before" "$after" -- deploy/site; then
  docker compose -f repo/deploy/site/compose.yaml --project-directory . up -d --wait
  docker compose -f repo/deploy/site/compose.yaml --project-directory . exec -T web nginx -s reload
fi
