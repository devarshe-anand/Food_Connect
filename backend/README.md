# FoodConnect backend

Node.js, Express, and TypeScript API starter for the FoodConnect project. The API is versioned under `/api/v1`; interactive OpenAPI documentation is served at `/api-docs`.

## Requirements

- Node.js 20 or newer
- npm
- Docker with Compose (for local PostgreSQL/PostGIS)

## Local setup

```sh
cd backend
npm install
cp .env.example .env
docker compose up -d db
npm run prisma:generate
npm run prisma:migrate -- --name init
npm run dev
```

The API listens on `http://localhost:3000`. Check `GET /api/v1/health` and open `http://localhost:3000/api-docs` for the starter API documentation.

The initial Prisma schema captures users, organizations, and donations. Geographic coordinates are represented as latitude/longitude fields for now; PostGIS is enabled in the local database image and a spatial migration/index can be added with the nearby matching implementation.

## Scripts

- `npm run dev` — run with automatic reload
- `npm run build` — compile to `dist/`
- `npm start` — run the compiled server
- `npm run typecheck` — check TypeScript without emitting files
- `npm run prisma:generate` — generate the Prisma client
- `npm run prisma:migrate -- --name <migration>` — create/apply a development migration
