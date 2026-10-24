#!/usr/bin/env bash
# Bring the stack on this server in line with the files next to this script.
#
# Runs on the server (GitHub Actions calls it over SSH after rsync, or run it
# by hand). Safe to run again: it only restarts what changed.
#
#   ./deploy.sh            render config, pull images, start or update
#   ./deploy.sh --check    render config and validate, change nothing
set -euo pipefail

cd "$(dirname "$0")"

CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

die() { echo "deploy: $*" >&2; exit 1; }

[[ -f .env ]] || die ".env is missing. Copy .env.example to .env and fill it in."
command -v envsubst >/dev/null || die "envsubst not found (apt install gettext-base)."

set -a
# shellcheck disable=SC1091
. ./.env
set +a

# Fail early on missing values instead of starting a half-configured Immich.
for var in DOMAIN PHOTOS_HOST ACME_EMAIL OAUTH_CLIENT_ID OAUTH_CLIENT_SECRET \
           DB_PASSWORD UPLOAD_LOCATION DB_DATA_LOCATION PASSWORD_LOGIN_ENABLED; do
  [[ -n "${!var:-}" ]] || die "$var is empty in .env"
done
[[ "$PASSWORD_LOGIN_ENABLED" == "true" || "$PASSWORD_LOGIN_ENABLED" == "false" ]] \
  || die "PASSWORD_LOGIN_ENABLED must be true or false"
[[ "$DB_PASSWORD" =~ ^[A-Za-z0-9]+$ ]] || die "DB_PASSWORD must be A-Za-z0-9 only"

# Render the Immich config. Only the listed variables are substituted, so a
# literal "$" anywhere else in the template is left alone.
rendered=immich/immich-config.yaml
old_hash=$(sha256sum "$rendered" 2>/dev/null | cut -d' ' -f1 || true)
umask 077
# shellcheck disable=SC2016  # the single quotes are intended: envsubst reads the names
envsubst '${PHOTOS_HOST} ${OAUTH_CLIENT_ID} ${OAUTH_CLIENT_SECRET} ${PASSWORD_LOGIN_ENABLED}' \
  < immich/immich-config.template.yaml > "$rendered.tmp"
mv "$rendered.tmp" "$rendered"
umask 022
new_hash=$(sha256sum "$rendered" | cut -d' ' -f1)

docker compose config --quiet
if ! out=$(docker compose run --rm --no-deps --quiet-pull --entrypoint caddy caddy \
             validate --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1); then
  echo "$out" >&2
  die "Caddyfile is invalid"
fi

if $CHECK_ONLY; then
  echo "deploy: config is valid (check only, nothing changed)"
  exit 0
fi

# Without the data volume, Immich would quietly fill the boot disk.
DATA_MOUNT="${DATA_MOUNT:-/srv/photos}"
mountpoint -q "$DATA_MOUNT" || [[ "${ALLOW_UNMOUNTED:-}" == "1" ]] \
  || die "$DATA_MOUNT is not mounted. Run scripts/mount-data-volume.sh first."

mkdir -p "$UPLOAD_LOCATION" "$DB_DATA_LOCATION"

docker compose pull --quiet
docker compose up --detach --remove-orphans --wait --wait-timeout 300

# Bind-mounted config does not trigger a container restart, so do it here.
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
if [[ "$old_hash" != "$new_hash" ]]; then
  echo "deploy: Immich config changed, restarting immich-server"
  docker compose restart immich-server
fi

docker image prune --force >/dev/null
docker compose ps
echo "deploy: done"
