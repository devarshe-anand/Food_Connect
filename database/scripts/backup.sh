#!/usr/bin/env bash
set -Eeuo pipefail

: "${DATABASE_URL:?Set DATABASE_URL to the database to back up}"
backup_dir="${BACKUP_DIR:-./backups}"
mkdir -p "$backup_dir"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="${backup_dir%/}/foodconnect-${timestamp}.dump"
backup_name="$(basename "$backup_file")"

pg_dump --dbname="$DATABASE_URL" --format=custom --no-owner --no-acl --file="$backup_file"
pg_restore --list "$backup_file" >/dev/null
(cd "$(dirname "$backup_file")" && sha256sum "$backup_name" > "${backup_name}.sha256")
echo "Verified backup: $backup_file"
