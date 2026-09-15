#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

ensure_root "$@"
require_command curl
require_command python3
load_model_config

install -d -m 0755 "$MODEL_DIR"

TREE_URL="https://huggingface.co/api/models/${MODEL_REPO}/tree/main?recursive=true&expand=true"
info "Consultando el listado actual de archivos de $MODEL_REPO."
tree_json="$(curl --fail --silent --show-error --location --retry 5 --retry-delay 2 "$TREE_URL")"

find_matching_files() {
    local requested_quant="$1"
    mapfile -t matching_files < <(
        MODEL_QUANT="$requested_quant" python3 -c '
import json
import os
import re
import sys

quant = os.environ["MODEL_QUANT"].lower()
pattern = re.compile(r"(?:^|[-_.])" + re.escape(quant) + r"(?:[-_.]|$)")
items = json.load(sys.stdin)
for item in items:
    if item.get("type") != "file":
        continue
    path = item.get("path", "")
    name = path.rsplit("/", 1)[-1].lower()
    if name.endswith(".gguf") and pattern.search(name):
        size = item.get("size")
        size = size if isinstance(size, int) else ""
        lfs = item.get("lfs") or {}
        oid = lfs.get("oid", "")
        print(f"{path}\t{size}\t{oid}")
' <<<"$tree_json"
    )
}

find_matching_files "$MODEL_QUANT"

if [[ "${#matching_files[@]}" -eq 0 && "$MODEL_QUANT" == "Q5_K_M" ]]; then
    warn "Q5_K_M no está disponible en el repositorio; se usará Q4_K_M como fallback."
    MODEL_QUANT="Q4_K_M"
    find_matching_files "$MODEL_QUANT"
    [[ "${#matching_files[@]}" -gt 0 ]] || die "Tampoco se encontró Q4_K_M en $MODEL_REPO."

    if grep -qE '^MODEL_QUANT=' "$CONFIG_FILE"; then
        sed -i "s/^MODEL_QUANT=.*/MODEL_QUANT=$MODEL_QUANT/" "$CONFIG_FILE"
    else
        printf '\nMODEL_QUANT=%s\n' "$MODEL_QUANT" >>"$CONFIG_FILE"
    fi
    info "Configuración actualizada a MODEL_QUANT=$MODEL_QUANT."
fi

if [[ "${#matching_files[@]}" -eq 0 ]]; then
    die "No se encontró ningún archivo GGUF para $MODEL_QUANT en $MODEL_REPO."
fi
if [[ "${#matching_files[@]}" -gt 1 ]]; then
    printf 'ERROR: Se encontraron varios archivos para %s; no se descargará ninguno:\n' "$MODEL_QUANT" >&2
    printf '  %s\n' "${matching_files[@]}" >&2
    die "Selecciona una variante inequívoca en el repositorio."
fi

IFS=$'\t' read -r model_filename remote_size remote_oid <<<"${matching_files[0]}"
model_basename="$(basename -- "$model_filename")"
destination="$MODEL_DIR/$model_basename"

if [[ -f "$destination" ]]; then
    local_size="$(stat -c '%s' "$destination")"
    if [[ -n "$remote_size" && "$local_size" == "$remote_size" ]]; then
        info "El modelo ya existe y coincide en tamaño: $destination"
        chown qwenllm:qwenllm "$destination"
        chmod 0640 "$destination"
        exit 0
    fi
    if [[ -n "$remote_size" && "$local_size" -gt "$remote_size" ]]; then
        die "El archivo local $destination es mayor que el remoto; revísalo o elimínalo manualmente antes de reintentar."
    fi
    info "Se reanudará una descarga incompleta de $destination."
else
    info "Se descargará únicamente $model_filename ($MODEL_QUANT)."
fi

download_url="https://huggingface.co/${MODEL_REPO}/resolve/main/${model_filename}?download=true"
curl --fail --silent --show-error --location --retry 5 --retry-delay 2 --continue-at - \
    --output "$destination" "$download_url"

if [[ -n "$remote_size" ]]; then
    downloaded_size="$(stat -c '%s' "$destination")"
    [[ "$downloaded_size" == "$remote_size" ]] || \
        die "La descarga terminó con tamaño $downloaded_size; se esperaba $remote_size. Puedes reanudarla ejecutando el script de nuevo."
fi

chown qwenllm:qwenllm "$destination"
chmod 0640 "$destination"
info "Modelo listo: $destination"
if [[ -n "$remote_oid" ]]; then
    info "Identificador LFS reportado por Hugging Face: $remote_oid"
fi
