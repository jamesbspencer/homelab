#!/bin/sh
set -e

BAO_ADDR="${BAO_ADDR:-http://openbao:8200}"
KEYS_FILE="${KEYS_FILE:-/openbao/unseal.keys}"
PASSWORDS_FILE="${PASSWORDS_FILE:-/unseal/.env.passwords}"
INTERVAL="${INTERVAL:-10}"

echo "[openbao-unseal] Auto-unseal service started. Monitoring ${BAO_ADDR}..."

WARNED=0
WAS_SEALED=0

while true; do
  # Check if OpenBao HTTP listener is responding
  if ! wget -q --spider "${BAO_ADDR}/v1/sys/health?uninitcode=200&sealedcode=200" 2>/dev/null; then
    sleep 3
    continue
  fi

  # Query seal status
  STATUS=$(wget -q -O - "${BAO_ADDR}/v1/sys/seal-status" 2>/dev/null || true)

  if echo "$STATUS" | grep -q '"sealed":true'; then
    WAS_SEALED=1
    echo "[openbao-unseal] Detected sealed OpenBao instance. Initiating unseal sequence..."

    # Collect keys from available files
    KEYS=""
    if [ -f "$KEYS_FILE" ]; then
      KEYS=$(grep -v '^[[:space:]]*#' "$KEYS_FILE" | grep -v '^[[:space:]]*$' || true)
    fi

    if [ -z "$KEYS" ] && [ -f "$PASSWORDS_FILE" ]; then
      KEYS=$(grep -i '^unseal_key' "$PASSWORDS_FILE" | cut -d '=' -f 2- | tr -d ' ' || true)
    fi

    if [ -z "$KEYS" ]; then
      if [ "$WARNED" -eq 0 ]; then
        echo "[openbao-unseal] Notice: OpenBao is sealed, but no unseal keys were found."
        echo "[openbao-unseal] Please add unseal keys as unseal_key_1=... in .env.passwords or in openbao/unseal.keys."
        WARNED=1
      fi
      sleep "$INTERVAL"
      continue
    fi

    # Submit unseal keys
    UNSEALED=0
    for K in $KEYS; do
      if [ -n "$K" ]; then
        RES=$(wget -q -O - --post-data="{\"key\":\"$K\"}" "${BAO_ADDR}/v1/sys/unseal" 2>/dev/null || true)
        if echo "$RES" | grep -q '"sealed":false'; then
          echo "[openbao-unseal] ✓ Success: OpenBao threshold reached. OpenBao is now unsealed!"
          UNSEALED=1
          WARNED=0
          break
        fi
      fi
    done

    if [ "$UNSEALED" -eq 0 ]; then
      echo "[openbao-unseal] Warning: Submitted available keys but unseal threshold was not yet reached."
    fi

  elif echo "$STATUS" | grep -q '"sealed":false'; then
    if [ "$WAS_SEALED" -eq 1 ]; then
      echo "[openbao-unseal] OpenBao status: Active and unsealed."
      WAS_SEALED=0
    fi
    WARNED=0
  fi

  sleep "$INTERVAL"
done
