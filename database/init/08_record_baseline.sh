#!/usr/bin/env bash
set -Eeuo pipefail

init_dir=/docker-entrypoint-initdb.d
checksum="$(
  for file in "$init_dir"/01_extensions.sql "$init_dir"/02_types.sql \
    "$init_dir"/03_tables.sql "$init_dir"/04_constraints.sql \
    "$init_dir"/05_indexes.sql "$init_dir"/06_functions.sql; do
    sha256sum "$file" | awk '{print $1}'
  done | sha256sum | awk '{print $1}'
)"

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=ON_ERROR_STOP=1 --set=checksum="$checksum" <<'SQL'
INSERT INTO schema_migrations (version, checksum)
VALUES ('0001_baseline', :'checksum')
ON CONFLICT (version) DO NOTHING;
SQL
