#!/bin/bash
set -euo pipefail

SKEY_DIR=/opt/brother/scanner/brscan-skey
log() { echo "[brscan-skey] $*"; }
die() { log "ERROR: $*"; exit 1; }

log "version $(cat /etc/brscan-skey-version 2>/dev/null || echo dev)"

[ -n "${SCANNER_IP:-}" ]    || die "SCANNER_IP is required (IP address of the Brother device)"
[ -n "${SCANNER_MODEL:-}" ] || die "SCANNER_MODEL is required (e.g. DCP-L2550DW, MFC-L2710DW)"
[ -d "$OUTPUT_DIR" ]        || die "OUTPUT_DIR $OUTPUT_DIR does not exist (mount a volume there)"

# Model must be known to brscan4 (otherwise brsaneconfig4 accepts it but scanning fails)
if ! grep -qhF "\"$SCANNER_MODEL\"" /opt/brother/scanner/brscan4/models4/*.ini; then
    die "model '$SCANNER_MODEL' is not supported by brscan4 (list: docker run --rm --entrypoint list-models devzwf/brscan-skey)"
fi

# Network scanner declaration for the brscan4 SANE backend (idempotent)
brsaneconfig4 -r "$SCANNER_NAME" >/dev/null 2>&1 || true
brsaneconfig4 -a name="$SCANNER_NAME" model="$SCANNER_MODEL" ip="$SCANNER_IP" >/dev/null

# Every "Scan to PC" target (File, Image, OCR, E-mail) runs the same script.
# user= is the name shown on the device screen.
cat > "$SKEY_DIR/brscan-skey.config" <<CONF
password=
IMAGE="bash  /opt/scan/scantofile.sh"
OCR="bash  /opt/scan/scantofile.sh"
EMAIL="bash  /opt/scan/scantofile.sh"
FILE="bash  /opt/scan/scantofile.sh"
SEMID=b
user=$SKEY_USER
CONF

# Set explicit host IP address if provided (fixes 'Connecting to PC' hangs on multi-interface/non-eth0 hosts)
if [ -n "${HOST_IP:-}" ]; then
    echo "ip_address=$HOST_IP" >> "$SKEY_DIR/brscan-skey.config"
    log "registered host callback IP: $HOST_IP"
fi

# Write community used to register with the device (SNMP SET)
echo "CommunityName=$SNMP_COMMUNITY" > "$SKEY_DIR/brscan-snmp.cfg"

mkdir -p "$OUTPUT_DIR/.brscan-tmp"
chown "$PUID:$PGID" "$OUTPUT_DIR/.brscan-tmp" || log "warning: cannot chown $OUTPUT_DIR/.brscan-tmp"

log "device $SCANNER_MODEL @ $SCANNER_IP, shown as '$SKEY_USER', output $OUTPUT_DIR ($PUID:$PGID)"
log "settings: ${SCAN_RESOLUTION} dpi, $SCAN_MODE, page $SCAN_PAGE_SIZE"
log "the device must allow SNMP v1/v2c read-write, otherwise it reports 'No PC found'"

# Without arguments brscan-skey-exe stays in the foreground
# (-f / -u are commands sent to an already running instance).
exec "$SKEY_DIR/brscan-skey-exe"
