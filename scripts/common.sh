#!/usr/bin/env bash
set -euo pipefail

# Shared paths and validation used by the operational scripts.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INSTALL_ROOT="${QWEN_INSTALL_ROOT:-/opt/qwen-coder}"
CONFIG_FILE="${QWEN_CONFIG_FILE:-$INSTALL_ROOT/config/qwen-coder.env}"
MODEL_DIR_DEFAULT="$INSTALL_ROOT/models"
LLAMA_DIR="$INSTALL_ROOT/llama.cpp"
LLAMA_BIN="$LLAMA_DIR/build/bin/llama-server"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf 'INFO: %s\n' "$*"
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "No se encontró la dependencia '$1'."
}

ensure_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            die "Este script necesita root. Instala sudo o ejecútalo como root."
        fi
        exec sudo -E "$SCRIPT_PATH" "$@"
    fi
}

load_model_config() {
    [[ -f "$CONFIG_FILE" ]] || die "No existe $CONFIG_FILE. Ejecuta install.sh o crea ese archivo desde .env.example."
    [[ -r "$CONFIG_FILE" ]] || die "No se puede leer $CONFIG_FILE."

    # The configuration intentionally uses shell-compatible KEY=value syntax.
    # shellcheck disable=SC1090
    set -a
    source "$CONFIG_FILE"
    set +a

    : "${MODEL_DIR:=$MODEL_DIR_DEFAULT}"
    : "${MODEL_REPO:?Falta MODEL_REPO en $CONFIG_FILE}"
    : "${MODEL_QUANT:?Falta MODEL_QUANT en $CONFIG_FILE}"

    case "${MODEL_QUANT^^}" in
        Q4_K_M|Q5_K_M) MODEL_QUANT="${MODEL_QUANT^^}" ;;
        *) die "MODEL_QUANT debe ser Q5_K_M o Q4_K_M." ;;
    esac
}

load_config() {
    load_model_config

    : "${LLAMA_API_KEY:?Falta LLAMA_API_KEY en $CONFIG_FILE}"
    : "${LLAMA_HOST:?Falta LLAMA_HOST en $CONFIG_FILE}"
    : "${LLAMA_PORT:?Falta LLAMA_PORT en $CONFIG_FILE}"
    : "${LLAMA_THREADS:?Falta LLAMA_THREADS en $CONFIG_FILE}"
    : "${LLAMA_THREADS_BATCH:?Falta LLAMA_THREADS_BATCH en $CONFIG_FILE}"
    : "${LLAMA_CONTEXT:?Falta LLAMA_CONTEXT en $CONFIG_FILE}"
    : "${LLAMA_PARALLEL:?Falta LLAMA_PARALLEL en $CONFIG_FILE}"
    : "${LLAMA_BATCH:?Falta LLAMA_BATCH en $CONFIG_FILE}"
    : "${LLAMA_UBATCH:?Falta LLAMA_UBATCH en $CONFIG_FILE}"

    [[ "$LLAMA_API_KEY" != "" && "$LLAMA_API_KEY" != "CHANGE_ME" ]] || \
        die "Configura una LLAMA_API_KEY real en $CONFIG_FILE antes de arrancar el servidor."
    [[ "$LLAMA_PORT" =~ ^[0-9]+$ && "$LLAMA_PORT" -ge 1 && "$LLAMA_PORT" -le 65535 ]] || \
        die "LLAMA_PORT debe ser un puerto entre 1 y 65535."

    local numeric_name numeric_value
    for numeric_name in LLAMA_THREADS LLAMA_THREADS_BATCH LLAMA_CONTEXT LLAMA_PARALLEL LLAMA_BATCH LLAMA_UBATCH; do
        numeric_value="${!numeric_name}"
        [[ "$numeric_value" =~ ^[0-9]+$ && "$numeric_value" -gt 0 ]] || \
            die "$numeric_name debe ser un entero positivo."
    done

}

resolve_model_path() {
    local quant_lower candidate_count
    quant_lower="${MODEL_QUANT,,}"
    [[ -d "$MODEL_DIR" ]] || die "No existe MODEL_DIR: $MODEL_DIR"

    mapfile -t model_candidates < <(
        find "$MODEL_DIR" -maxdepth 1 -type f -iname "*${quant_lower}*.gguf" -print | sort
    )
    candidate_count="${#model_candidates[@]}"

    if [[ "$candidate_count" -eq 0 ]]; then
        die "No hay un modelo GGUF para $MODEL_QUANT en $MODEL_DIR. Ejecuta scripts/download-model.sh."
    fi
    if [[ "$candidate_count" -gt 1 ]]; then
        printf 'ERROR: Hay varios modelos para %s en %s:\n' "$MODEL_QUANT" "$MODEL_DIR" >&2
        printf '  %s\n' "${model_candidates[@]}" >&2
        die "Deja un único archivo para la cuantización seleccionada."
    fi

    MODEL_PATH="${model_candidates[0]}"
}

validate_server_options() {
    local help_text option
    [[ -x "$LLAMA_BIN" ]] || die "No existe el binario ejecutable $LLAMA_BIN. Ejecuta scripts/install.sh."
    help_text="$($LLAMA_BIN --help 2>&1)" || die "No se pudo ejecutar '$LLAMA_BIN --help'."

    for option in \
        --model --alias --host --port --threads --threads-batch --ctx-size \
        --parallel --batch-size --ubatch-size --cache-prompt --cont-batching --api-key; do
        grep -Fq -- "$option" <<<"$help_text" || \
            die "La versión instalada de llama-server no reconoce $option. Revisa su --help y actualiza el script."
    done

    if grep -Fq -- '--n-gpu-layers' <<<"$help_text"; then
        GPU_LAYERS_OPTION='--n-gpu-layers'
    elif grep -Fq -- '--gpu-layers' <<<"$help_text"; then
        GPU_LAYERS_OPTION='--gpu-layers'
    else
        die "La versión instalada no expone una opción equivalente a --n-gpu-layers."
    fi
}
