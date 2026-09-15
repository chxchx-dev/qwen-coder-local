#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

ensure_root "$@"
require_command systemctl
load_config

service_source="$PROJECT_ROOT/systemd/qwen-coder.service"
[[ -f "$service_source" ]] || die "No se encontró la unidad systemd en $service_source. Ejecuta install.sh desde el repositorio completo."
[[ -x "$INSTALL_ROOT/scripts/start.sh" ]] || die "No existe el runner instalado en $INSTALL_ROOT/scripts/start.sh. Ejecuta install.sh."

install -m 0644 "$service_source" /etc/systemd/system/qwen-coder.service
systemctl daemon-reload

info "Unidad instalada: /etc/systemd/system/qwen-coder.service"
info "Para arrancar: sudo systemctl enable --now qwen-coder"
