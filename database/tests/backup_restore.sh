#!/usr/bin/env bash
set -Eeuo pipefail

: "${DATABASE_URL:?Set DATABASE_URL to a disposable source database}"
: "${RESTORE_TEST_DATABASE_URL:?Set RESTORE_TEST_DATABASE_URL to a different disposable restore database}"

source_database="$(psql "$DATABASE_URL" -X -At -v ON_ERROR_STOP=1 -c 'SELECT current_database()')"
restore_database="$(psql "$RESTORE_TEST_DATABASE_URL" -X -At -v ON_ERROR_STOP=1 -c 'SELECT current_database()')"
if [[ "$source_database" == "$restore_database" ]]; then
  echo "Source and restore target database names must differ." >&2
  exit 1
fi

test_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$test_dir"
}
trap cleanup EXIT

BACKUP_DIR="$test_dir" DATABASE_URL="$DATABASE_URL" \
  bash "$(dirname "${BASH_SOURCE[0]}")/../scripts/backup.sh"
backup_file="$(find "$test_dir" -maxdepth 1 -type f -name '*.dump' -print -quit)"
if [[ -z "$backup_file" ]]; then
  echo "Backup script did not create an archive." >&2
  exit 1
fi

DATABASE_URL="$RESTORE_TEST_DATABASE_URL" BACKUP_FILE="$backup_file" CONFIRM_RESTORE=YES \
  bash "$(dirname "${BASH_SOURCE[0]}")/../scripts/restore.sh"
restored="$(psql "$RESTORE_TEST_DATABASE_URL" -X -At -v ON_ERROR_STOP=1 \
  -c "SELECT to_regclass('public.users') IS NOT NULL AND to_regclass('public.donations') IS NOT NULL")"
if [[ "$restored" != "t" ]]; then
  echo "Restored database is missing required tables." >&2
  exit 1
fi
echo "Backup integrity and restore round trip verified."
