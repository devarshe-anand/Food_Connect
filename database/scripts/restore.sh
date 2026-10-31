#!/usr/bin/env bash
set -Eeuo pipefail

: "${DATABASE_URL:?Set DATABASE_URL to the database to restore into}"
: "${BACKUP_FILE:?Set BACKUP_FILE to a verified custom-format pg_dump file}"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "Backup file does not exist: $BACKUP_FILE" >&2
  exit 1
fi

if [[ "${CONFIRM_RESTORE:-}" != "YES" ]]; then
  echo "Restore replaces objects in the target database. Set CONFIRM_RESTORE=YES to proceed." >&2
  exit 1
fi

pg_restore --list "$BACKUP_FILE" >/dev/null
if [[ -f "${BACKUP_FILE}.sha256" ]]; then
  (cd "$(dirname "$BACKUP_FILE")" && sha256sum --check "$(basename "$BACKUP_FILE").sha256")
fi
pg_restore --dbname="$DATABASE_URL" --clean --if-exists --no-owner --no-acl --single-transaction "$BACKUP_FILE"
echo "Restore completed from: $BACKUP_FILE"
