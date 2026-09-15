#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

require_command curl
require_command python3
require_command awk
require_command free
require_command ps
require_command sed
load_config

QWEN_BASE_URL="${QWEN_BASE_URL:-http://127.0.0.1:${LLAMA_PORT}/v1}"
QWEN_API_KEY="${QWEN_API_KEY:-$LLAMA_API_KEY}"
QWEN_MODEL="${QWEN_MODEL:-qwen2.5-coder-14b}"
QWEN_BASE_URL="${QWEN_BASE_URL%/}"
HEALTH_URL="${QWEN_BASE_URL%/v1}/health"

[[ -n "$QWEN_API_KEY" ]] || die "Define QWEN_API_KEY o configura LLAMA_API_KEY."

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

printf '=== qwen-coder-server benchmark ===\n'
printf 'Base URL: %s\n' "$QWEN_BASE_URL"
printf 'Modelo:   %s\n\n' "$QWEN_MODEL"

curl --fail --silent --show-error "$HEALTH_URL" >/dev/null || \
    die "El servidor no está healthy en $HEALTH_URL. Revisa: journalctl -u qwen-coder -f"

ram_used_mib() {
    free -m | awk '/^Mem:/ { print $3 " MiB usados / " $2 " MiB totales"; found=1 } END { if (!found) print "no disponible" }'
}

server_rss_mib() {
    ps -C llama-server -o rss= 2>/dev/null | awk '{ total += $1 } END { if (total == "") total = 0; printf "%d MiB", total / 1024 }'
}

load_average() {
    awk '{ print $1 " / " $2 " / " $3 }' /proc/loadavg
}

run_test() {
    local label="$1"
    local prompt="$2"
    local max_tokens="$3"
    local response_file="$temp_dir/${label}.json"
    local meta http_code elapsed total_tokens tokens_per_second
    local ram_before ram_after rss_before rss_after load_before load_after

    ram_before="$(ram_used_mib)"
    rss_before="$(server_rss_mib)"
    load_before="$(load_average)"

    if ! meta="$(curl --silent --show-error \
        --output "$response_file" \
        --write-out '%{http_code}\t%{time_total}' \
        -X POST "$QWEN_BASE_URL/chat/completions" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $QWEN_API_KEY" \
        --data "$(python3 - "$QWEN_MODEL" "$prompt" "$max_tokens" <<'PY'
import json
import sys

model, prompt, max_tokens = sys.argv[1], sys.argv[2], int(sys.argv[3])
print(json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "temperature": 0.2,
    "max_tokens": max_tokens,
    "stream": False,
}))
PY
    )")"; then
        die "La petición de benchmark '$label' no pudo conectarse con $QWEN_BASE_URL/chat/completions."
    fi

    IFS=$'\t' read -r http_code elapsed <<<"$meta"
    ram_after="$(ram_used_mib)"
    rss_after="$(server_rss_mib)"
    load_after="$(load_average)"

    if [[ "$http_code" != "200" ]]; then
        printf '\n[%s] HTTP %s\n' "$label" "$http_code" >&2
        sed -n '1,120p' "$response_file" >&2
        return 1
    fi

    read -r total_tokens tokens_per_second < <(python3 - "$response_file" "$elapsed" <<'PY'
import json
import sys

path, elapsed = sys.argv[1], float(sys.argv[2])
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
usage = data.get("usage") or {}
timings = data.get("timings") or {}
tokens = usage.get("completion_tokens") or timings.get("predicted_n") or 0
n = int(tokens)
rate = (n / elapsed) if elapsed > 0 and n else 0.0
print(n, f"{rate:.2f}")
PY
    )

    printf '[%s]\n' "$label"
    printf '  tiempo total:       %ss\n' "$elapsed"
    printf '  tokens generados:   %s\n' "$total_tokens"
    printf '  tokens/segundo:      %s\n' "$tokens_per_second"
    printf '  RAM sistema antes:   %s\n' "$ram_before"
    printf '  RAM sistema después: %s\n' "$ram_after"
    printf '  RSS llama-server:    %s -> %s\n' "$rss_before" "$rss_after"
    printf '  carga CPU (1/5/15):  %s -> %s\n\n' "$load_before" "$load_after"
}

run_test "prompt-corto" \
    "Responde únicamente con: servidor listo." \
    32
run_test "generacion-256" \
    "Explica en pasos breves cómo organizar un proyecto Python pequeño y mantenible." \
    256
run_test "generacion-1024" \
    "Describe una estrategia completa para revisar, probar y desplegar una API HTTP en producción." \
    1024
run_test "prompt-codigo" \
    "Escribe una función TypeScript que valide un correo electrónico, con tipos explícitos y una prueba unitaria." \
    256
