#!/bin/sh
# Entry point for the MoMoE / Strata container. The engine is compiled during docker
# build and lives in the image, so the first start only downloads the model.
# The install config is kept on the /data volume so a recreated container skips
# the setup pass and goes straight to serving.
set -e
cd /opt/strata || exit 1

if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ] && [ "$1" != "setup.py" ]; then
  exec "$@"
fi

cpuinfo="${STRATA_CPUINFO:-/proc/cpuinfo}"
if [ -r "$cpuinfo" ] && grep -q '^flags' "$cpuinfo" && ! grep -m1 '^flags' "$cpuinfo" | grep -qw avx2; then
  echo "WARNING: this host CPU has no AVX2. The engine in this image is built for CPUs with AVX2, so it may stop" >&2
  echo "  with 'illegal instruction' (exit 132). Build the image on this machine (docker build), which compiles the" >&2
  echo "  engine for the CPU it runs on, and see docs/INSTALL.md (Older CPUs, experimental) for the older-CPU build." >&2
fi

STRATA_DATA="${STRATA_DATA:-/data}"
FAMILY="${FAMILY:-ornith}"
MODEL="${MODEL:-IQ4_XS}"
CONTEXT="${CONTEXT:-65536}"
VISION="${VISION:-no}"          # no | yes | cpu (the image encoder on the CPU)
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
API_KEY="${API_KEY:-}"
KV="${KV:-}"                    # int8 | q4_0 | k8v4; empty: setup.py's own default (int8)
GPUS="${GPUS:-}"                # "0,2" or "all": one model across several cards (docs/MULTI_GPU.md)
GPU="${GPU:-}"                  # one card, numbered as nvidia-smi numbers them
LAYER_SPLIT="${LAYER_SPLIT:-}"  # with GPUS: where each later card's layers start (default: auto)
LOW_RAM="${LOW_RAM:-auto}"      # on: the experts come from the pack's experts.bin, not from RAM
GGUF_DIR="${GGUF_DIR:-}"        # a mounted folder with GGUF files you already have: no download
RESIDENT_BUDGET_GIB="${RESIDENT_BUDGET_GIB:-}"   # UD-Q4_K_XL: GiB of experts kept in RAM (default: setup's pick)
KV_STREAMING="${KV_STREAMING:-}" # auto | on | off; empty: setup.py's own default (auto)
VRAM_RESERVE_MIB="${VRAM_RESERVE_MIB:-}" # VRAM in MiB left free for other programs (e.g., Ollama embeddings)
CONFIG="${CONFIG:-}"            # a config file to start with (wins over MODEL's /data/config/strata-<model>.json)

case "$FAMILY" in qwen) prefix="" ;; *) prefix="${FAMILY}-" ;; esac
tag="${prefix}$(printf '%s' "$MODEL" | tr 'A-Z' 'a-z')"
cfg_name="strata-$tag.json"
cfg="$STRATA_DATA/config/$cfg_name"

mkdir -p "$STRATA_DATA/config" "$STRATA_DATA/logs"
if [ ! -L /opt/strata/config ]; then
  rm -rf /opt/strata/config
  ln -sfn "$STRATA_DATA/config" /opt/strata/config
fi
if [ ! -L /opt/strata/logs ]; then
  rm -rf /opt/strata/logs
  ln -sfn "$STRATA_DATA/logs" /opt/strata/logs
fi

target_cfg="${CONFIG:-$cfg}"

if [ -n "$CONFIG" ]; then
  [ -f "$CONFIG" ] || { echo "CONFIG=$CONFIG does not exist." >&2; exit 1; }
  echo "Config: $CONFIG (from CONFIG)"
elif [ "${REINSTALL:-0}" = "1" ] || [ ! -f "$cfg" ]; then
  if [ -n "$GGUF_DIR" ]; then
    echo "Setting up $tag from the GGUF files in $GGUF_DIR (the engine is already in the image)."
  else
    echo "Setting up $tag: downloading the model (the engine is already in the image)."
  fi
  set -- --family "$FAMILY" --model "$MODEL" --context "$CONTEXT" --vision "$VISION" \
    --data-dir "$STRATA_DATA" --config-name "$cfg_name" --host "$HOST" --api-key "$API_KEY" \
    --port "$PORT" --no-start --low-ram "$LOW_RAM"
  if [ -n "$KV" ]; then set -- "$@" --kv "$KV"; fi
  if [ -n "$GPUS" ]; then set -- "$@" --gpus "$GPUS"; fi
  if [ -n "$GPU" ]; then set -- "$@" --gpu "$GPU"; fi
  if [ -n "$LAYER_SPLIT" ]; then set -- "$@" --layer-split "$LAYER_SPLIT"; fi
  if [ -n "$GGUF_DIR" ]; then set -- "$@" --gguf-dir "$GGUF_DIR"; fi
  if [ -n "$RESIDENT_BUDGET_GIB" ]; then set -- "$@" --resident-budget-gib "$RESIDENT_BUDGET_GIB"; fi
  if [ -n "$KV_STREAMING" ]; then set -- "$@" --kv-streaming "$KV_STREAMING"; fi
  if [ -n "$VRAM_RESERVE_MIB" ]; then set -- "$@" --vram-reserve-mib "$VRAM_RESERVE_MIB"; fi
  .venv/bin/python setup.py --setup --yes "$@"
  echo "Config: $cfg (from FAMILY=$FAMILY MODEL=$MODEL, just set up)"
else
  echo "Config: $cfg (from FAMILY=$FAMILY MODEL=$MODEL)"
fi

set -- --config "$target_cfg" --port "$PORT" --yes
if [ -n "$HOST" ]; then set -- "$@" --host "$HOST"; fi
if [ -n "$API_KEY" ]; then set -- "$@" --api-key "$API_KEY"; fi
if [ -n "$GPUS" ]; then set -- "$@" --gpus "$GPUS"; fi
if [ -n "$GPU" ]; then set -- "$@" --gpu "$GPU"; fi
if [ -n "$LAYER_SPLIT" ]; then set -- "$@" --layer-split "$LAYER_SPLIT"; fi
if [ -n "$VRAM_RESERVE_MIB" ]; then set -- "$@" --vram-reserve-mib "$VRAM_RESERVE_MIB"; fi
exec .venv/bin/python setup.py "$@"
