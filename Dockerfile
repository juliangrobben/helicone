FROM clickhouse/clickhouse-server:24.3.13.40 AS database-stage

# Install PostgreSQL and other dependencies
RUN apt-get update && apt-get install -y \
    postgresql-common \
    python3.11 \
    python3.11-dev \
    python3-pip \
    openjdk-17-jre-headless \
    wget \
    unzip \
    curl \
    supervisor \
    && /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y \
    && apt-get install -y \
    postgresql-17 \
    postgresql-client-17 \
    postgresql-contrib-17 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Flyway directly
RUN wget -q -O flyway.tar.gz https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/10.5.0/flyway-commandline-10.5.0.tar.gz \
    && mkdir -p /opt/flyway \
    && tar -xzf flyway.tar.gz -C /opt/flyway --strip-components=1 \
    && rm flyway.tar.gz \
    && ln -s /opt/flyway/flyway /usr/local/bin/flyway \
    && flyway -v

# Install Python dependencies
RUN pip3 install --no-cache-dir requests clickhouse-driver tabulate yarl

# Create supervisord directories and copy configuration
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

ENV FLYWAY_URL=jdbc:postgresql://localhost:5432/helicone_test
ENV FLYWAY_USER=postgres
ENV FLYWAY_PASSWORD=password
ENV FLYWAY_LOCATIONS=filesystem:/app/supabase/migrations,filesystem:/app/supabase/migrations_without_supabase
ENV FLYWAY_SQL_MIGRATION_PREFIX=
ENV FLYWAY_SQL_MIGRATION_SEPARATOR=_
ENV FLYWAY_SQL_MIGRATION_SUFFIXES=.sql


COPY ./supabase/migrations /app/supabase/migrations
COPY ./supabase/migrations_without_supabase /app/supabase/migrations_without_supabase
COPY ./clickhouse/migrations /app/clickhouse/migrations
COPY ./clickhouse/ch_hcone.py /app/clickhouse/ch_hcone.py
RUN chmod +x /app/clickhouse/ch_hcone.py

RUN service postgresql start && \
    su - postgres -c "createdb helicone_test" && \
    su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD 'password';\"" && \
    service postgresql stop

# --------------------------------------------------------------------------------------------------------------------

FROM database-stage AS jawn-stage

# Install Node.js 20 and yarn
RUN apt-get update && apt-get install -y curl \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy package files and source code
WORKDIR /app
COPY package.json package.json
COPY yarn.lock yarn.lock
COPY web/package.json web/package.json
COPY packages ./packages
COPY shared ./shared
COPY valhalla ./valhalla
RUN find /app -name ".env.*" -exec rm {} \;

# Install dependencies and build jawn
RUN yarn install \
    && cd valhalla/jawn \
    && yarn install \
    && yarn build


# --------------------------------------------------------------------------------------------------------------------

FROM jawn-stage AS web-stage

# Copy package files and source code
WORKDIR /app
COPY web ./web
RUN find /app -name ".env.*" -exec rm {} \;

# Install dependencies and build web
RUN yarn install \
    && cd web \
    && yarn install \
    && yarn build

# --------------------------------------------------------------------------------------------------------------------

FROM web-stage AS minio-stage

# Install MinIO server and client
RUN wget -q -O /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-amd64/minio \
    && chmod +x /usr/local/bin/minio \
    && wget -q -O /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc \
    && chmod +x /usr/local/bin/mc

# Create MinIO data directory
RUN mkdir -p /data

ENV POSTGRES_DB=helicone_test
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=password
ENV CLICKHOUSE_DEFAULT_USER=default

ENV CLICKHOUSE_HOST=http://localhost:8123

ENV MINIO_ROOT_USER=minioadmin
ENV MINIO_ROOT_PASSWORD=minioadmin


# Use supervisord as entrypoint
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

# --------------------------------------------------------------------------------------------------------------------
FROM helicone/ai-gateway:latest AS gateway-stage