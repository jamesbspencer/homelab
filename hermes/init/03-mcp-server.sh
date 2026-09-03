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
