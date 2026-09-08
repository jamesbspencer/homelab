#!/bin/sh
set -e
# Recreate s6 service slot for hermes-mcp-server on container boot
mkdir -p /run/service/mcp-server
cat << 'EOF' > /run/service/mcp-server/run
#!/command/with-contenv sh
set -e
export HOME=/opt/data
cd /opt/data
. /opt/hermes/.venv/bin/activate
exec s6-setuidgid hermes python3 /opt/data/scripts/hermes_mcp_server.py
EOF
chmod +x /run/service/mcp-server/run
chown -R hermes:hermes /run/service/mcp-server

# Patch self-hosted OIDC plugin so stale/malformed cookies are handled as expired/invalid rather than unreachable IDP
python3 -c '
import os
path = "/opt/hermes/plugins/dashboard_auth/self_hosted/__init__.py"
if os.path.exists(path):
    c = open(path).read()
    old = "except jwt.PyJWKClientError as exc:\n            raise ProviderError(f\"JWKS lookup failed: {exc}\") from exc\n        except Exception as exc:"
    new = "except jwt.PyJWKClientError as exc:\n            raise ProviderError(f\"JWKS lookup failed: {exc}\") from exc\n        except (jwt.DecodeError, jwt.InvalidTokenError) as exc:\n            raise InvalidCodeError(f\"Malformed ID token: {exc}\") from exc\n        except Exception as exc:"
    if old in c:
        open(path, "w").write(c.replace(old, new, 1))
'

# Append Agent Vault Root CA to system and virtualenv cert stores if not already present
if [ -f /opt/data/ca.pem ] && ! grep -q "Agent Vault Root CA" /etc/ssl/certs/ca-certificates.crt 2>/dev/null; then
    cat /opt/data/ca.pem >> /etc/ssl/certs/ca-certificates.crt
fi
CERTIFI_FILE="$(/opt/hermes/.venv/bin/python3 -m certifi 2>/dev/null || true)"
if [ -f /opt/data/ca.pem ] && [ -n "$CERTIFI_FILE" ] && [ -f "$CERTIFI_FILE" ]; then
    if ! grep -q "Agent Vault Root CA" "$CERTIFI_FILE" 2>/dev/null; then
        cat /opt/data/ca.pem >> "$CERTIFI_FILE"
    fi
fi

