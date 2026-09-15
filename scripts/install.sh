#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INSTALL_ROOT="/opt/qwen-coder"
LLAMA_DIR="$INSTALL_ROOT/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODEL_DIR="$INSTALL_ROOT/models"
LOG_DIR="$INSTALL_ROOT/logs"
CONFIG_DIR="$INSTALL_ROOT/config"

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

if [[ "${EUID}" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        die "Este script necesita root. Instala sudo o ejecútalo como root."
    fi
    exec sudo -E "$SCRIPT_PATH" "$@"
fi

[[ -r /etc/os-release ]] || die "No se pudo detectar el sistema operativo."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "Se requiere Ubuntu 22.04 o 24.04; sistema detectado: ${ID:-desconocido}."
case "${VERSION_ID:-}" in
    22.04|24.04) ;;
    *) die "Se requiere Ubuntu 22.04 o 24.04; versión detectada: ${VERSION_ID:-desconocida}." ;;
esac
[[ "$(uname -m)" == "x86_64" ]] || die "Se requiere arquitectura x86_64; detectada: $(uname -m)."

export DEBIAN_FRONTEND=noninteractive
info "Actualizando el índice de paquetes APT."
apt-get update

info "Instalando dependencias de compilación y descarga."
apt-get install -y \
    git \
    git-lfs \
    curl \
    wget \
    cmake \
    build-essential \
    pkg-config \
    libopenblas-dev \
    python3 \
    python3-pip

git lfs install --system

info "Creando usuario y directorios del servicio."
if ! id -u qwenllm >/dev/null 2>&1; then
    useradd --system --home-dir "$INSTALL_ROOT" --shell /usr/sbin/nologin --no-create-home qwenllm
fi

install -d -m 0755 "$INSTALL_ROOT"
install -d -m 0755 "$MODEL_DIR"
install -d -m 0750 -o root -g qwenllm "$CONFIG_DIR"
install -d -m 0750 -o qwenllm -g qwenllm "$LOG_DIR"
install -d -m 0755 "$INSTALL_ROOT/scripts"
install -d -m 0755 "$INSTALL_ROOT/systemd"

if [[ ! -e "$LLAMA_DIR" ]]; then
    info "Clonando llama.cpp en $LLAMA_DIR."
    git clone https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
elif [[ ! -d "$LLAMA_DIR/.git" ]]; then
    die "$LLAMA_DIR existe pero no es un checkout Git de llama.cpp."
else
    info "El checkout existente de llama.cpp se conserva; usa la sección de actualización del README para actualizarlo."
fi

info "Instalando copias operativas de scripts y unidad systemd."
for script_file in "$PROJECT_ROOT"/scripts/*.sh; do
    install -m 0755 "$script_file" "$INSTALL_ROOT/scripts/$(basename "$script_file")"
done
install -m 0644 "$PROJECT_ROOT/systemd/qwen-coder.service" "$INSTALL_ROOT/systemd/qwen-coder.service"

info "Configurando CMake para CPU x86_64 en modo Release."
cmake_args=(
    -S "$LLAMA_DIR"
    -B "$BUILD_DIR"
    -DCMAKE_BUILD_TYPE=Release
    -DLLAMA_BUILD_SERVER=ON
    -DGGML_NATIVE=ON
)

if cmake "${cmake_args[@]}" -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS; then
    info "OpenBLAS habilitado."
else
    warn "La configuración con OpenBLAS falló; se reintentará sin BLAS porque la versión puede haber cambiado sus opciones."
    cmake "${cmake_args[@]}" -DGGML_BLAS=OFF
fi

info "Compilando llama-server y llama-cli."
cmake --build "$BUILD_DIR" --config Release --target llama-server llama-cli --parallel "$(nproc)"

[[ -x "$LLAMA_DIR/build/bin/llama-server" ]] || die "La compilación no produjo llama-server."
[[ -x "$LLAMA_DIR/build/bin/llama-cli" ]] || die "La compilación no produjo llama-cli."
"$LLAMA_DIR/build/bin/llama-server" --help >/dev/null
"$LLAMA_DIR/build/bin/llama-cli" --help >/dev/null

info "Ajustando permisos para que qwenllm pueda leer binarios y modelos."
chown -R root:root "$LLAMA_DIR"
chmod -R a+rX "$LLAMA_DIR"
chown -R qwenllm:qwenllm "$MODEL_DIR" "$LOG_DIR"
chmod 0755 "$MODEL_DIR"
chmod 0750 "$LOG_DIR"

if [[ ! -f "$CONFIG_DIR/qwen-coder.env" ]]; then
    install -m 0640 -o root -g qwenllm "$PROJECT_ROOT/.env.example" "$CONFIG_DIR/qwen-coder.env"
    info "Se creó la configuración inicial en $CONFIG_DIR/qwen-coder.env."
else
    info "La configuración existente se conserva: $CONFIG_DIR/qwen-coder.env"
fi
chown root:qwenllm "$CONFIG_DIR/qwen-coder.env"
chmod 0640 "$CONFIG_DIR/qwen-coder.env"

info "Instalación terminada. Edita $CONFIG_DIR/qwen-coder.env antes de iniciar el servicio."
