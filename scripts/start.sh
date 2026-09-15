#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

SERVICE_NAME="qwen-coder"

if [[ "${1:-}" != "--direct" ]]; then
    [[ "$#" -eq 0 ]] || die "Uso: $0 [--direct]"
    require_command systemctl
    if [[ "${EUID}" -eq 0 ]]; then
        exec systemctl start "$SERVICE_NAME"
    fi
    require_command sudo
    exec sudo systemctl start "$SERVICE_NAME"
fi

[[ "$#" -eq 1 ]] || die "Uso: $0 [--direct]"
load_config
resolve_model_path
validate_server_options

info "Arrancando llama-server con $MODEL_PATH"
info "CPU: threads=$LLAMA_THREADS, threads-batch=$LLAMA_THREADS_BATCH, context=$LLAMA_CONTEXT, parallel=$LLAMA_PARALLEL"
info "mmap queda en el modo predeterminado de llama.cpp (auto); mlock no se habilita."

exec "$LLAMA_BIN" \
    --model "$MODEL_PATH" \
    --alias qwen2.5-coder-14b \
    --host "$LLAMA_HOST" \
    --port "$LLAMA_PORT" \
    --threads "$LLAMA_THREADS" \
    --threads-batch "$LLAMA_THREADS_BATCH" \
    --ctx-size "$LLAMA_CONTEXT" \
    --parallel "$LLAMA_PARALLEL" \
    --batch-size "$LLAMA_BATCH" \
    --ubatch-size "$LLAMA_UBATCH" \
    "$GPU_LAYERS_OPTION" 0 \
    --cache-prompt \
    --cont-batching \
    --api-key "$LLAMA_API_KEY"
