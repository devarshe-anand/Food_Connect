# FoodConnect backend

Node.js, Express, and TypeScript API starter for FoodConnect. The API is versioned under
`/api/v1`; interactive OpenAPI documentation is served at `/api-docs`.

## Requirements

- Node.js 20 or newer
- npm
- Docker with Compose (for local PostgreSQL 17/PostGIS)

## Local setup

From the repository root, copy `database/.env.example` to `database/.env`, replace the
password placeholders with separate strong secrets, and start the database:

```powershell
Copy-Item database\.env.example database\.env
docker compose --env-file database\.env -f database\docker-compose.yml up -d --build
```

Set `backend/.env` from the backend example and use the app role's `DATABASE_URL`:

```dotenv
NODE_ENV=development
PORT=3000
DATABASE_URL=postgresql://foodconnect_app:<APP_DB_PASSWORD>@127.0.0.1:5432/foodconnect
LOG_LEVEL=info
```

Then start the API:

```sh
cd backend
npm install
npm run prisma:generate
npm run dev
```

The API listens on `http://localhost:3000`. Check `GET /api/v1/health` and visit
`http://localhost:3000/api-docs`. Startup verifies the configured database connection;
the health route also runs a lightweight database query and reports HTTP 503 if the
database is unavailable.

## Database source of truth

`database/init/` and `database/migrations/` contain the authoritative PostgreSQL schema,
PostGIS geography definitions, transactional workflow functions, and database migrations.
Prisma models in `prisma/schema.prisma` are mapped to these SQL-managed tables. Geographic
fields use Prisma's unsupported native type and should be queried/updated with parameterized
raw SQL. Do not use `prisma migrate dev` or `prisma db push`; they would conflict with the
SQL-owned schema and its security/partial-index/function definitions.

Apply database changes using a migration-owner URL:

```sh
MIGRATIONS_DATABASE_URL='postgresql://foodconnect_admin:<password>@127.0.0.1:5432/foodconnect' \
  npm run db:migrate
```

Read [the database guide](../database/README.md) for schema, matching, concurrency, outbox,
backup/restore, and test instructions.

## Backend scripts

- `npm run dev` — run with automatic reload
- `npm run build` — compile to `dist/`
- `npm start` — run the compiled server
- `npm run typecheck` — check TypeScript without emitting files
- `npm run prisma:generate` — generate the mapped Prisma client
- `npm run db:migrate` — apply versioned SQL migrations (requires Bash, `psql`, and `sha256sum`)
