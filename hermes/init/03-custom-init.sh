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

# Patch skills hub to filter directory entries in downloaded bundles/zips before quarantine
python3 -c '
import os

clawhub_path = "/opt/hermes/tools/skills_hub_clawhub.py"
if os.path.exists(clawhub_path):
    c = open(clawhub_path).read()
    old = """                with zipfile.ZipFile(archive) as zf:
                    for info in zf.infolist():
                        if info.is_dir():
                            continue"""
    new = """                with zipfile.ZipFile(archive) as zf:
                    _all_names = [i.filename.rstrip("/") for i in zf.infolist()]
                    _dir_prefixes = {"/".join(p[:idx]) for p in [n.split("/") for n in _all_names] for idx in range(1, len(p))}
                    for info in zf.infolist():
                        if info.is_dir() or info.filename.rstrip("/") in _dir_prefixes:
                            continue"""
    if old in c:
        open(clawhub_path, "w").write(c.replace(old, new, 1))

install_path = "/opt/hermes/tools/skills_hub_install.py"
if os.path.exists(install_path):
    c = open(install_path).read()
    old = """    # Validate every path before touching disk so a bad member aborts cleanly.
    validated_files = [(_validate_bundle_rel_path(rel_path), content) for rel_path, content in bundle.files.items()]"""
    new = """    # Validate every path before touching disk so a bad member aborts cleanly.
    validated_files = [(_validate_bundle_rel_path(rel_path), content) for rel_path, content in bundle.files.items()]
    _dir_prefixes = {"/".join(p[:idx]) for p in [r.split("/") for r, _ in validated_files] for idx in range(1, len(p))}
    validated_files = [(r, c) for r, c in validated_files if r not in _dir_prefixes]"""
    if old in c:
        open(install_path, "w").write(c.replace(old, new, 1))
'


