#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${MIGRATIONS_DATABASE_URL:?Set MIGRATIONS_DATABASE_URL to a migration-owner connection string}"

psql "$MIGRATIONS_DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS public.schema_migrations (
  version VARCHAR(100) PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  checksum VARCHAR(128) NOT NULL
);
SQL

while IFS= read -r migration; do
  version="$(basename "$migration" .sql)"
  if [[ "$version" == "0001_baseline" ]]; then
    checksum="$(
      for file in "$ROOT_DIR"/init/01_extensions.sql "$ROOT_DIR"/init/02_types.sql \
        "$ROOT_DIR"/init/03_tables.sql "$ROOT_DIR"/init/04_constraints.sql \
        "$ROOT_DIR"/init/05_indexes.sql "$ROOT_DIR"/init/06_functions.sql; do
        sha256sum "$file" | awk '{print $1}'
      done | sha256sum | awk '{print $1}'
    )"
  else
    checksum="$(sha256sum "$migration" | awk '{print $1}')"
  fi
  printf -v migration_psql_path "'%s'" "${migration//\'/\'\\\'\'}"
  echo "Checking migration: $version"
  psql "$MIGRATIONS_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
    -v version="$version" -v checksum="$checksum" -v migration_file="$migration_psql_path" <<'SQL'
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('foodconnect_schema_migrations'));
SELECT EXISTS (
  SELECT 1 FROM public.schema_migrations WHERE version = :'version'
) AS already_applied \gset
SELECT (
  COALESCE((
    SELECT checksum = :'checksum'
    FROM public.schema_migrations WHERE version = :'version'
  ), FALSE)
) AS checksum_matches \gset
\if :already_applied
  \if :checksum_matches
    \echo Skipping already-applied migration :version
  \else
    \echo Migration checksum mismatch for :version. Create a new migration.
    \quit 3
  \endif
\else
  \i :migration_file
  INSERT INTO public.schema_migrations(version, checksum)
  VALUES (:'version', :'checksum');
  \echo Applied migration :version
\endif
COMMIT;
SQL
done < <(find "$ROOT_DIR/migrations" -maxdepth 1 -type f -name '*.sql' -print | sort)
