#!/usr/bin/env bash
set -Eeuo pipefail

DB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose=(docker compose --env-file "$DB_DIR/.env" -f "$DB_DIR/docker-compose.yml")
table_name="persistence_probe_$$"
probe_id="$(cat /proc/sys/kernel/random/uuid)"

cleanup() {
  "${compose[@]}" exec -T db sh -c \
    'psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "$1"' sh \
    "DROP TABLE IF EXISTS public.$table_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${compose[@]}" up -d --wait db
"${compose[@]}" exec -T db sh -c \
  'psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$1"' sh \
  "CREATE TABLE public.$table_name (id UUID PRIMARY KEY); INSERT INTO public.$table_name VALUES ('$probe_id');"
"${compose[@]}" restart db
"${compose[@]}" up -d --wait db
"${compose[@]}" exec -T db sh -c \
  'psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -At -v ON_ERROR_STOP=1 -c "$1"' sh \
  "SELECT id FROM public.$table_name;" | grep -Fx "$probe_id"
echo "Persistence across container restart verified."
