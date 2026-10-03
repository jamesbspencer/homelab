#!/bin/bash
set -e

# Enable vector extension on primary database
echo "Enabling pgvector extension on primary database '$POSTGRES_DB'..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL

# Conditionally provision dedicated database & user for Hindsight
if [ -n "$HINDSIGHT_POSTGRES_DB" ]; then
    HINDSIGHT_USER="${HINDSIGHT_POSTGRES_USER:-hindsight}"
    HINDSIGHT_PASS="${HINDSIGHT_POSTGRES_PASSWORD:-$POSTGRES_PASSWORD}"

    echo "Provisioning dedicated user '$HINDSIGHT_USER' and database '$HINDSIGHT_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$HINDSIGHT_USER') THEN
                CREATE ROLE "$HINDSIGHT_USER" WITH LOGIN PASSWORD '$HINDSIGHT_PASS';
            END IF;
        END
        \$\$;
        SELECT 'CREATE DATABASE "$HINDSIGHT_POSTGRES_DB" OWNER "$HINDSIGHT_USER"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$HINDSIGHT_POSTGRES_DB')\gexec
        GRANT ALL PRIVILEGES ON DATABASE "$HINDSIGHT_POSTGRES_DB" TO "$HINDSIGHT_USER";
EOSQL

    echo "Enabling pgvector extension on '$HINDSIGHT_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$HINDSIGHT_POSTGRES_DB" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
fi

# Conditionally provision dedicated database & user for LiteLLM
if [ -n "$LITELLM_POSTGRES_DB" ]; then
    LITELLM_USER="${LITELLM_POSTGRES_USER:-litellm}"
    LITELLM_PASS="${LITELLM_POSTGRES_PASSWORD:-$POSTGRES_PASSWORD}"

    echo "Provisioning dedicated user '$LITELLM_USER' and database '$LITELLM_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$LITELLM_USER') THEN
                CREATE ROLE "$LITELLM_USER" WITH LOGIN PASSWORD '$LITELLM_PASS';
            END IF;
        END
        \$\$;
        SELECT 'CREATE DATABASE "$LITELLM_POSTGRES_DB" OWNER "$LITELLM_USER"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$LITELLM_POSTGRES_DB')\gexec
        GRANT ALL PRIVILEGES ON DATABASE "$LITELLM_POSTGRES_DB" TO "$LITELLM_USER";
EOSQL

    echo "Enabling pgvector extension on '$LITELLM_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$LITELLM_POSTGRES_DB" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
fi

# Conditionally provision dedicated database & user for Authentik
if [ -n "$AUTHENTIK_POSTGRES_DB" ]; then
    AUTHENTIK_USER="${AUTHENTIK_POSTGRES_USER:-authentik}"
    AUTHENTIK_PASS="${AUTHENTIK_POSTGRES_PASSWORD:-$POSTGRES_PASSWORD}"

    echo "Provisioning dedicated user '$AUTHENTIK_USER' and database '$AUTHENTIK_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$AUTHENTIK_USER') THEN
                CREATE ROLE "$AUTHENTIK_USER" WITH LOGIN PASSWORD '$AUTHENTIK_PASS';
            END IF;
        END
        \$\$;
        SELECT 'CREATE DATABASE "$AUTHENTIK_POSTGRES_DB" OWNER "$AUTHENTIK_USER"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$AUTHENTIK_POSTGRES_DB')\gexec
        GRANT ALL PRIVILEGES ON DATABASE "$AUTHENTIK_POSTGRES_DB" TO "$AUTHENTIK_USER";
EOSQL
fi

# Conditionally provision dedicated database & user for Gitea
if [ -n "$GITEA_POSTGRES_DB" ]; then
    GITEA_USER="${GITEA_POSTGRES_USER:-gitea}"
    GITEA_PASS="${GITEA_POSTGRES_PASSWORD:-$POSTGRES_PASSWORD}"

    echo "Provisioning dedicated user '$GITEA_USER' and database '$GITEA_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$GITEA_USER') THEN
                CREATE ROLE "$GITEA_USER" WITH LOGIN PASSWORD '$GITEA_PASS';
            END IF;
        END
        \$\$;
        SELECT 'CREATE DATABASE "$GITEA_POSTGRES_DB" OWNER "$GITEA_USER"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$GITEA_POSTGRES_DB')\gexec
        GRANT ALL PRIVILEGES ON DATABASE "$GITEA_POSTGRES_DB" TO "$GITEA_USER";
EOSQL
# Conditionally provision dedicated database & user for Memlord
if [ -n "$MEMLORD_POSTGRES_DB" ]; then
    MEMLORD_USER="${MEMLORD_POSTGRES_USER:-memlord}"
    MEMLORD_PASS="${MEMLORD_POSTGRES_PASSWORD:-$POSTGRES_PASSWORD}"

    echo "Provisioning dedicated user '$MEMLORD_USER' and database '$MEMLORD_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$MEMLORD_USER') THEN
                CREATE ROLE "$MEMLORD_USER" WITH LOGIN PASSWORD '$MEMLORD_PASS';
            END IF;
        END
        \$\$;
        SELECT 'CREATE DATABASE "$MEMLORD_POSTGRES_DB" OWNER "$MEMLORD_USER"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$MEMLORD_POSTGRES_DB')\gexec
        GRANT ALL PRIVILEGES ON DATABASE "$MEMLORD_POSTGRES_DB" TO "$MEMLORD_USER";
EOSQL

    echo "Enabling pgvector extension on '$MEMLORD_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$MEMLORD_POSTGRES_DB" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
fi

echo "pgvector initialization completed successfully."


