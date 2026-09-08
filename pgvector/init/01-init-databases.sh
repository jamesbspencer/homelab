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

# Conditionally provision dedicated database & user for Agent Vault
if [ -n "$AGENTVAULT_POSTGRES_DB" ]; then
    AGENTVAULT_USER="${AGENTVAULT_POSTGRES_USER:-agentvault}"
    AGENTVAULT_PASS="${AGENTVAULT_POSTGRES_PASSWORD:-$POSTGRES_PASSWORD}"

    echo "Provisioning dedicated user '$AGENTVAULT_USER' and database '$AGENTVAULT_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$AGENTVAULT_USER') THEN
                CREATE ROLE "$AGENTVAULT_USER" WITH LOGIN PASSWORD '$AGENTVAULT_PASS';
            END IF;
        END
        \$\$;
        SELECT 'CREATE DATABASE "$AGENTVAULT_POSTGRES_DB" OWNER "$AGENTVAULT_USER"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$AGENTVAULT_POSTGRES_DB')\gexec
        GRANT ALL PRIVILEGES ON DATABASE "$AGENTVAULT_POSTGRES_DB" TO "$AGENTVAULT_USER";
EOSQL
fi

# Conditionally provision dedicated database & user for Infisical Secret Manager
if [ -n "$INFISICAL_POSTGRES_DB" ]; then
    INFISICAL_USER="${INFISICAL_POSTGRES_USER:-infisical}"
    INFISICAL_PASS="${INFISICAL_POSTGRES_PASSWORD:-$POSTGRES_PASSWORD}"

    echo "Provisioning dedicated user '$INFISICAL_USER' and database '$INFISICAL_POSTGRES_DB'..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$INFISICAL_USER') THEN
                CREATE ROLE "$INFISICAL_USER" WITH LOGIN PASSWORD '$INFISICAL_PASS';
            END IF;
        END
        \$\$;
        SELECT 'CREATE DATABASE "$INFISICAL_POSTGRES_DB" OWNER "$INFISICAL_USER"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$INFISICAL_POSTGRES_DB')\gexec
        GRANT ALL PRIVILEGES ON DATABASE "$INFISICAL_POSTGRES_DB" TO "$INFISICAL_USER";
EOSQL
fi

echo "pgvector initialization completed successfully."

