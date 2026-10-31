# Food Connect PostgreSQL

Production-oriented PostgreSQL 17 + PostGIS infrastructure for Food Connect. The database
is authoritative for donation eligibility, single-winner acceptance, handover state, and
transactional notification events. Supabase Storage retains image/document bytes; database
columns contain only storage object paths.

## Architecture

```mermaid
erDiagram
  USERS ||--o{ ORGANIZATION_MEMBERS : joins
  ORGANIZATIONS ||--o{ ORGANIZATION_MEMBERS : has
  ORGANIZATIONS ||--o{ ORGANIZATION_DOCUMENTS : submits
  USERS o|--o{ ORGANIZATION_DOCUMENTS : reviews
  ORGANIZATIONS ||--o{ DONATIONS : donates
  ORGANIZATIONS o|--o{ DONATIONS : accepts
  DONATIONS ||--o{ DONATION_CLAIMS : offered_to
  ORGANIZATIONS ||--o{ DONATION_CLAIMS : NGO
  USERS o|--o{ NOTIFICATIONS : receives
  ORGANIZATIONS o|--o{ NOTIFICATIONS : receives
  DONATIONS o|--o{ NOTIFICATIONS : concerns
  DONATIONS ||--o{ HANDOVER_CONFIRMATIONS : confirmed
  ORGANIZATIONS ||--o{ HANDOVER_CONFIRMATIONS : confirms
  USERS ||--o{ HANDOVER_CONFIRMATIONS : acts
  USERS o|--o{ AUDIT_LOGS : performs
  DONATIONS ||--o{ NOTIFICATION_OUTBOX : emits
  USERS ||--o{ REFRESH_TOKENS : owns
```

## Tables

| Table | Responsibility |
|---|---|
| `users` | Account, password hash, platform role, verification state, and soft deletion. Email is case-insensitively unique among non-deleted accounts. Optional phone numbers are unique among non-deleted accounts and must be normalized to E.164 by the API. |
| `organizations` | Donor or NGO identity, registration, address, verification/operational state, and PostGIS registered location. |
| `organization_members` | User membership and organization-local role/status. A pair is unique; active membership lookup is indexed. |
| `organization_documents` | Verification metadata and Supabase Storage paths; reviewer and review timestamps are constrained together. |
| `donations` | Food, quantity/unit, pickup deadline/address/geography, lifecycle, donor, and accepted NGO. |
| `donation_claims` | Per-NGO notification and acceptance record. Unique per donation/NGO; a partial unique index permits only one accepted claim per donation. |
| `notifications` | Durable in-app notification content and recipient, with idempotent insertion. |
| `handover_confirmations` | Exactly one donor and one NGO confirmation per donation, with optional evidence path. |
| `audit_logs` | Actor, action, entity, JSONB before/after snapshots, and UTC timestamp. Entity references are polymorphic by design and therefore not foreign-keyed. |
| `notification_outbox` | Transactional integration events with idempotency keys, lease-based workers, retry count, and dead-letter state. |
| `refresh_tokens` | Token hashes only, expiration, revocation, and optional rotation link. |
| `schema_migrations` | Applied migration version/checksum ledger, required to make schema changes sequential and idempotent. |

Enums constrain account, organization, document, donation, claim, notification, handover,
and outbox states. Main entities use UUID primary keys and `TIMESTAMPTZ` values.

## Docker setup

From the repository root, copy `database/.env.example` to `database/.env` and replace both
passwords with distinct long random values. Do not commit `.env`.

```powershell
Copy-Item database\.env.example database\.env
docker compose --env-file database\.env -f database\docker-compose.yml build
docker compose --env-file database\.env -f database\docker-compose.yml up -d
docker compose --env-file database\.env -f database\docker-compose.yml ps
docker compose --env-file database\.env -f database\docker-compose.yml logs -f db
docker compose --env-file database\.env -f database\docker-compose.yml down
```

The `db` service builds a custom image from the PostgreSQL 17 + PostGIS image, runs
`database/init/*` only for an empty named volume, and stores data in the persistent
`foodconnect-postgres` volume. The host port is bound to `127.0.0.1` by default, not a
public interface. Compose also places the service on an internal bridge network. `down`
does not remove data. `down -v` destroys the database volume and must not be used as a
backup or routine cleanup command.

Credentials are passed as environment variables for bootstrap and app roles; protect
`database/.env` and use a managed secrets provider in deployed environments.
`foodconnect_admin` owns schema installation. `foodconnect_app` is non-superuser,
has read access and limited writes, and must use the provided database functions for
claims, handover, and outbox operations. Provide a separate migration-owner connection
for schema migrations.

### Connection strings

For a backend running on the host:

```dotenv
DATABASE_URL=postgresql://foodconnect_app:<APP_DB_PASSWORD>@127.0.0.1:5432/foodconnect
```

For a backend container attached to the same Compose network, use `db` as the hostname:

```dotenv
DATABASE_URL=postgresql://foodconnect_app:<APP_DB_PASSWORD>@db:5432/foodconnect
```

Set `DATABASE_URL` in the backend's ignored `.env`. URL-encode special characters in the
password. The existing backend already validates `DATABASE_URL` at startup; its current
health endpoint does not yet execute a database query.

## Matching and claims

Find eligible verified, active NGOs in the fixed 5,000-meter radius. The function returns
UUID and geodesic distance in meters; no degree-based distance approximation is used.

```sql
SELECT ngo_organization_id, distance_meters
FROM match_eligible_ngos(
  ST_SetSRID(ST_MakePoint(77.5946, 12.9716), 4326)::geography
);
```

After inserting a donation, call this function within the same application transaction to
record claim rows, user notifications, and outbox events:

```sql
SELECT notify_eligible_ngos(:'donation_id', :'actor_user_id');
```

Platform administrators review organizations and their documents through audited database
functions; the app role cannot directly modify reviewer/status fields:

```sql
SELECT review_organization(:'organization_id', :'admin_user_id', 'VERIFIED', NULL);
SELECT review_organization_document(:'document_id', :'admin_user_id', 'APPROVED', NULL);
```

Membership changes are also audited and restricted to an active owner/admin, with a
first-owner bootstrap path for an organization that has no members and invite acceptance
by the invited user:

```sql
SELECT manage_organization_member(
  :'organization_id', :'actor_user_id', :'member_user_id', 'MEMBER', 'INVITED'
);
```

The NGO acceptance operation locks the donation row, checks the notified claim, checks
current NGO eligibility and active membership, updates the donation and accepted claim,
and creates audit/in-app/outbox records atomically:

```sql
SELECT * FROM accept_donation(:'donation_id', :'ngo_organization_id', :'actor_user_id');
```

Only the first transaction can change `AVAILABLE` to `CLAIMED`. The partial unique index
on accepted claims provides a second integrity barrier.

```sql
SELECT confirm_handover(
  :'donation_id', :'organization_id', :'actor_user_id', 'DONOR', :'evidence_path'
);
-- The NGO invokes the same function with confirmation type 'NGO'.
```

The first valid confirmation sets `COLLECTED`; the second sets `COMPLETED`. The function
checks the confirming organization and active member, prevents duplicate side confirmations,
and writes audit and outbox entries in the same transaction.

## Outbox worker operations

Workers claim events with a unique worker UUID. `FOR UPDATE SKIP LOCKED` lets multiple
workers run concurrently; expired leases are reclaimed. Send externally with the event's
`idempotency_key` as the provider idempotency key, then mark success or schedule retry:

```sql
SELECT * FROM claim_notification_outbox(:'worker_uuid', 25, 60);
SELECT complete_notification_outbox(:'event_id', :'worker_uuid');
SELECT fail_notification_outbox(:'event_id', :'worker_uuid', 'provider error details');
```

Retries use capped exponential backoff; events reaching `max_attempts` become `DEAD` for
operator inspection. Delivery is at-least-once, so downstream delivery must be idempotent.

## Initialization and migrations

Initialization SQL in `init/` executes in filename order on an empty data volume. It
creates extensions, types, tables, constraints, indexes, functions, application grants,
and baseline migration record. Development seed data is deliberately not copied into the
image and is never loaded automatically:

```sh
psql "$MIGRATIONS_DATABASE_URL" -v ON_ERROR_STOP=1 -f database/seeds/development_seed.sql
```

`migrations/` is separate from fresh-volume initialization. Apply versioned SQL in order
with an owner/admin connection (requires `psql`, `sha256sum`, and Bash):

```sh
MIGRATIONS_DATABASE_URL='postgresql://foodconnect_admin:...@localhost:5432/foodconnect' \
  bash database/scripts/migrate.sh
```

The runner serializes migration processes with a PostgreSQL advisory lock, wraps each
migration and ledger entry in a transaction, and rejects edits to already-applied
migrations. `0001_baseline.sql` reuses canonical initialization SQL and is recorded during
fresh initialization. Add a new numbered SQL migration for each future change; never edit
an applied migration. A migration file must not start or commit its own transaction;
the runner owns the transaction. Prefer forward fixes. Rollback is not automatic: destructive or
data-transforming changes need a separately reviewed recovery migration or a verified
restore, since reversing data loss is not generally possible.

## Backups and restore

Install PostgreSQL client tools compatible with PostgreSQL 17. Backups are custom-format
files written to the host filesystem, not the database container or Docker volume:

```sh
DATABASE_URL='postgresql://foodconnect_admin:...@localhost:5432/foodconnect' \
  BACKUP_DIR='./backups' bash database/scripts/backup.sh
```

The script validates the archive using `pg_restore --list` and writes a SHA-256 checksum.
Restore is destructive to conflicting objects in the chosen target database and requires
an explicit confirmation:

```sh
DATABASE_URL='postgresql://foodconnect_admin:...@localhost:5432/foodconnect' \
  BACKUP_FILE='./backups/foodconnect-<timestamp>.dump' \
  CONFIRM_RESTORE=YES bash database/scripts/restore.sh
```

Test restores regularly in a separate database. A Docker volume is not a backup.

## Tests and persistence

Run the transactional schema/workflow assertions against a disposable initialized DB:

```sh
psql "$MIGRATIONS_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f database/tests/schema_tests.sql
```

It checks extensions, 5 km inclusion/exclusion, notification and outbox creation,
acceptance, second-claim rejection, handover, completion, and audit records. The test
rolls back its fixture. The genuinely concurrent two-connection procedure is documented
in [`tests/concurrency_tests.md`](./tests/concurrency_tests.md).

Run restart-persistence and backup/restore round-trip checks against disposable resources:

```sh
bash database/tests/container_persistence.sh
DATABASE_URL='postgresql://foodconnect_admin:...@localhost:5432/foodconnect' \
RESTORE_TEST_DATABASE_URL='postgresql://foodconnect_admin:...@localhost:5432/foodconnect_restore_test' \
  bash database/tests/backup_restore.sh
```

The restore test overwrites conflicting objects in its explicitly named disposable target.

## Indexing decisions

- Partial GiST index on eligible NGO locations and GiST index on donation pickup points
  support PostGIS geography distance queries.
- Status/deadline and donor/accepted-NGO indexes support listing and lifecycle operations.
- Partial unique indexes enforce one accepted NGO per donation and active membership
  uniqueness without blocking historical membership records.
- Partial unread-notification, pending-outbox, expired-lease, verification-queue, and
  active-token indexes target common filtered workloads and remain smaller than full indexes.
- Case-insensitive unique email and optional normalized phone indexes implement the
  documented account identity policy.

## Troubleshooting

- **Health check does not pass:** inspect `docker compose logs db`; verify bootstrap
  passwords and port availability.
- **PostGIS is missing:** inspect `SELECT postgis_full_version();`; ensure the custom image
  built from the configured PostGIS 17 tag.
- **Backend cannot connect:** confirm the host uses `127.0.0.1`, containers use `db`,
  credentials match `APP_DB_USER`/`APP_DB_PASSWORD`, and special URL characters are encoded.
- **Initialization did not rerun:** PostgreSQL only executes init files for an empty data
  directory. Preserve data and apply a versioned migration rather than deleting the volume.
- **App role cannot alter schema:** expected. Use the migration-owner URL for the migration
  runner; do not grant the runtime role superuser or schema ownership.
- **Port conflicts:** set `DB_PORT` in `database/.env`; keep the bind address loopback unless
  access is restricted by a trusted network and firewall.
