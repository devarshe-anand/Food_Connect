ARG POSTGIS_IMAGE=postgis/postgis:17-3.5
FROM ${POSTGIS_IMAGE}

LABEL org.opencontainers.image.title="Food Connect PostgreSQL"
LABEL org.opencontainers.image.description="PostgreSQL 17 with PostGIS and Food Connect schema initialization"

COPY init/ /docker-entrypoint-initdb.d/
RUN chmod 0755 /docker-entrypoint-initdb.d/*.sh
