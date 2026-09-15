#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="qwen-coder"
if ! command -v systemctl >/dev/null 2>&1; then
    printf 'ERROR: systemctl no está disponible en este sistema.\n' >&2
    exit 1
fi

if [[ "${EUID}" -eq 0 ]]; then
    exec systemctl stop "$SERVICE_NAME"
fi
command -v sudo >/dev/null 2>&1 || {
    printf 'ERROR: detener el servicio requiere root o sudo.\n' >&2
    exit 1
}
exec sudo systemctl stop "$SERVICE_NAME"
