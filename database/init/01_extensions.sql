CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

SELECT format('ALTER DATABASE %I SET timezone TO %L', current_database(), 'UTC') \gexec
