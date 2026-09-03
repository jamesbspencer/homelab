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

echo "pgvector initialization completed successfully."
