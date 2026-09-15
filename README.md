# qwen-coder-server

Servidor pequeño y autocontenido para ejecutar `Qwen2.5-Coder-14B-Instruct-Uncensored-GGUF` con `llama.cpp` en Ubuntu 22.04/24.04, CPU-only, y exponer una API HTTP compatible con OpenAI.

No instala Docker ni Ollama. Está pensado para un host x86_64 con 12 cores y 48 GiB de RAM, con una única generación pesada a la vez (`parallel=1`).

## 1. Requisitos

- Ubuntu 22.04 o 24.04.
- Arquitectura x86_64.
- 12 cores de CPU y 48 GiB de RAM recomendados.
- Acceso `sudo` y conexión a Internet.
- Al menos unos 15 GiB libres para `Q5_K_M`; el modelo de este repositorio figura actualmente con aproximadamente 10.5 GB.
- Una API key privada. No la guardes en Git.

La instalación compila `llama-server` y `llama-cli` desde el checkout actual de `llama.cpp` usando CMake y OpenBLAS cuando la opción sigue disponible.

## 2. Instalación

Desde el servidor:

```bash
git clone <REPO_URL> qwen-coder-server
cd qwen-coder-server
sudo ./scripts/install.sh
```

`install.sh`:

- verifica Ubuntu 22.04/24.04 y x86_64;
- instala `git`, `git-lfs`, `curl`, `wget`, `cmake`, `build-essential`, `pkg-config`, `libopenblas-dev`, `python3` y `python3-pip`;
- crea `/opt/qwen-coder`, `/opt/qwen-coder/models` y `/opt/qwen-coder/logs`;
- crea el usuario de sistema `qwenllm`;
- clona `llama.cpp` en `/opt/qwen-coder/llama.cpp`;
- compila en modo Release los targets `llama-server` y `llama-cli`;
- instala copias operativas de los scripts bajo `/opt/qwen-coder/scripts`.

La compilación usa estas opciones actuales de CMake:

```bash
cmake -S /opt/qwen-coder/llama.cpp \
  -B /opt/qwen-coder/llama.cpp/build \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_SERVER=ON \
  -DGGML_NATIVE=ON \
  -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=OpenBLAS
```

Si una versión futura de `llama.cpp` deja de aceptar OpenBLAS, el instalador muestra el error y reintenta una compilación CPU sin BLAS. No se habilita CUDA.

## 3. Configuración

La plantilla completa es [.env.example](.env.example). El instalador crea inicialmente:

```text
/opt/qwen-coder/config/qwen-coder.env
```

Copia la plantilla y edítala antes de arrancar. El instalador ya crea una copia inicial para que la descarga predeterminada `Q5_K_M` pueda ejecutarse inmediatamente; si quieres cambiar la cuantización antes de descargar, copia y edita primero:

```bash
sudo cp .env.example /opt/qwen-coder/config/qwen-coder.env
sudo nano /opt/qwen-coder/config/qwen-coder.env
```

Configura como mínimo una API key aleatoria y privada:

```bash
# Genera una key alfanumérica segura y cópiala al archivo de configuración.
python3 -c 'import secrets; print(secrets.token_urlsafe(32))'

LLAMA_API_KEY=pon_aqui_una_key_larga_y_privada
```

Valores iniciales CPU:

```text
LLAMA_HOST=0.0.0.0
LLAMA_PORT=8080
LLAMA_THREADS=12
LLAMA_THREADS_BATCH=12
LLAMA_CONTEXT=8192
LLAMA_PARALLEL=1
LLAMA_BATCH=512
LLAMA_UBATCH=256
MODEL_DIR=/opt/qwen-coder/models
MODEL_REPO=BlossomsAI/Qwen2.5-Coder-14B-Instruct-Uncensored-GGUF
MODEL_QUANT=Q5_K_M
```

`MODEL_QUANT` acepta `Q5_K_M` y `Q4_K_M`. El runner usa `mmap` mediante el modo predeterminado actual de llama.cpp (`auto`), y no activa `mlock`.

## 4. Descarga del modelo

El script consulta primero el listado actual de archivos del repositorio Hugging Face. No presupone el nombre del GGUF: busca exactamente la cuantización configurada, exige una coincidencia única y descarga solo ese archivo.

```bash
sudo ./scripts/download-model.sh
```

La variante que existe actualmente se identifica como `q5_k_m.gguf`; si se selecciona `Q4_K_M`, el script detecta `q4_k_m.gguf`. Si en el futuro `Q5_K_M` desaparece del repositorio, el script cambia la configuración a `Q4_K_M` y descarga solo ese fallback. Si el archivo ya existe y coincide en tamaño, no vuelve a descargarlo. Si una descarga se interrumpe, `curl` la reanuda.

Para cambiar de cuantización:

```bash
sudo sed -i 's/^MODEL_QUANT=.*/MODEL_QUANT=Q4_K_M/' /opt/qwen-coder/config/qwen-coder.env
sudo ./scripts/download-model.sh
```

No se descargan automáticamente ambas cuantizaciones. Si conservas dos archivos, el runner solo arrancará cuando encuentre una coincidencia inequívoca para la cuantización seleccionada.

## 5. Ejecución manual

Para ejecutar con systemd, instala la unidad:

```bash
sudo ./scripts/install-service.sh
sudo systemctl enable --now qwen-coder
```

Comandos operativos equivalentes:

```bash
sudo ./scripts/start.sh
sudo ./scripts/stop.sh
sudo ./scripts/status.sh
```

El arranque verifica contra `llama-server --help` que los flags usados siguen existiendo. Si llama.cpp cambia un alias, el script acepta el equivalente actual para las capas GPU (`--n-gpu-layers` o `--gpu-layers`) y falla con un mensaje claro para cualquier otro cambio.

Para depuración directa, detén primero el servicio y ejecuta como el usuario no privilegiado:

```bash
sudo systemctl stop qwen-coder
sudo -u qwenllm /opt/qwen-coder/scripts/start.sh --direct
```

Pulsa `Ctrl-C` para terminar la ejecución manual.

## 6. systemd

La unidad instalada es `/etc/systemd/system/qwen-coder.service` y carga:

```text
/opt/qwen-coder/config/qwen-coder.env
```

El proceso corre como `qwenllm`, no como root, con `Restart=always`, `RestartSec=5`, límites de archivos adecuados, límites de memoria de 40/44 GiB y salida al journal.

```bash
sudo systemctl daemon-reload
sudo systemctl enable qwen-coder
sudo systemctl start qwen-coder
sudo systemctl status qwen-coder --no-pager
```

Health check local:

```bash
curl http://127.0.0.1:8080/health
```

Una respuesta `503` durante la carga inicial es normal. Cuando está listo devuelve HTTP 200 y `{"status":"ok"}`. El endpoint de health es público según la interfaz de llama.cpp; las rutas de la API se protegen con la API key.

## 7. Firewall

No uses `ufw allow 8080` como regla general: expondría el endpoint a cualquier origen permitido por el firewall.

### Opción A: solo la IP pública del PC

Sustituye `MI_IP_PUBLICA` por una IP concreta y conserva SSH antes de activar UFW:

```bash
sudo ufw allow OpenSSH
sudo ufw default deny incoming
sudo ufw allow from MI_IP_PUBLICA to any port 8080 proto tcp
sudo ufw enable
sudo ufw status verbose
```

### Opción B: Tailscale o WireGuard — recomendada

No abras 8080 a Internet. Permite únicamente la interfaz privada de la VPN:

```bash
sudo ufw allow OpenSSH
sudo ufw default deny incoming
sudo ufw allow in on tailscale0 to any port 8080 proto tcp
sudo ufw enable
sudo ufw status verbose
```

Para WireGuard, cambia `tailscale0` por `wg0`. Consume el servicio usando la IP privada de Tailscale/WireGuard, por ejemplo `http://100.x.y.z:8080/v1`.

## 8. Conexión remota

Comprueba desde el servidor:

```bash
curl http://127.0.0.1:8080/health
```

Desde el PC remoto, con firewall y ruta configurados:

```bash
curl http://SERVER_IP:8080/v1/models \
  -H "Authorization: Bearer API_KEY"
```

Si usas VPN, reemplaza `SERVER_IP` por la IP de Tailscale/WireGuard. No compartas la API key en capturas, repositorios o historiales shell compartidos.

## 9. curl y API OpenAI-compatible

La API base es:

```text
http://SERVER_IP:8080/v1
```

Ejemplo de chat completion:

```bash
SERVER_URL="http://SERVER_IP:8080/v1"
API_KEY="API_KEY"

curl -sS "$SERVER_URL/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "qwen2.5-coder-14b",
    "messages": [
      {
        "role": "system",
        "content": "You are an expert software engineering assistant."
      },
      {
        "role": "user",
        "content": "Create a TypeScript function that validates an email address."
      }
    ],
    "temperature": 0.2,
    "max_tokens": 1024
  }'
```

Esto permite usar el servidor desde scripts Python, Node.js, VS Code, OpenCode, agentes propios y aplicaciones internas que admitan un endpoint OpenAI-compatible. Usa el modelo `qwen2.5-coder-14b` que se establece mediante `--alias`.

## 10. Python

El cliente incluido usa el SDK oficial de OpenAI y no contiene IP ni API key:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade openai

export QWEN_BASE_URL="http://SERVER_IP:8080/v1"
export QWEN_API_KEY="API_KEY"
export QWEN_MODEL="qwen2.5-coder-14b"
python examples/client.py
```

El archivo es [examples/client.py](examples/client.py).

## 11. Node.js

Instala el SDK oficial y ejecuta el ejemplo incluido:

```bash
npm install openai
export QWEN_BASE_URL="http://SERVER_IP:8080/v1"
export QWEN_API_KEY="API_KEY"
node examples/client.mjs
```

El archivo es [examples/client.mjs](examples/client.mjs).

## 12. VS Code, Continue, OpenCode y agentes

Configura en el cliente que uses:

- Base URL: `http://SERVER_IP:8080/v1`.
- API key: el valor de `LLAMA_API_KEY`.
- Model: `qwen2.5-coder-14b`.
- Proveedor/protocolo: OpenAI-compatible.

En conexiones remotas, usa preferentemente la IP de Tailscale/WireGuard o una regla UFW limitada a tu IP. Algunas extensiones llaman primero a `/v1/models`; esa llamada debe llevar `Authorization: Bearer API_KEY`.

Para conectar VS Code con Continue paso a paso, consulta [CONTINUE_VSCODE.md](CONTINUE_VSCODE.md). El ejemplo de configuración YAML está en [examples/continue-config.yaml](examples/continue-config.yaml). La API key se configura localmente mediante el archivo `.env` de Continue y no se guarda en este repositorio.

## 13. Troubleshooting

### `401 Invalid API Key`

Comprueba que el cliente usa la misma cadena que `LLAMA_API_KEY` y reinicia tras cambiar configuración:

```bash
sudo systemctl restart qwen-coder
sudo journalctl -u qwen-coder -n 80 --no-pager
```

### `health` devuelve `503`

El modelo sigue cargando o el proceso falló:

```bash
sudo systemctl status qwen-coder --no-pager
sudo journalctl -u qwen-coder -f
```

### Modelo no encontrado

Comprueba la cuantización y vuelve a ejecutar:

```bash
grep -E '^(MODEL_DIR|MODEL_REPO|MODEL_QUANT)=' /opt/qwen-coder/config/qwen-coder.env
sudo ./scripts/download-model.sh
```

### Memoria o rendimiento insuficiente

El orden recomendado es reducir `LLAMA_CONTEXT` a `4096`, probar `Q4_K_M`, y mantener `LLAMA_PARALLEL=1`. No empieces con contextos 32768, 65536 o 131072 en este host.

### El puerto no responde remotamente

Comprueba escucha, firewall y ruta:

```bash
sudo ss -ltnp | grep ':8080'
sudo ufw status verbose
curl -v http://127.0.0.1:8080/health
```

### Ver el proceso manualmente

```bash
htop
journalctl -u qwen-coder -f
```

## 14. Benchmarking

El benchmark realiza cuatro pruebas: prompt corto, 256 tokens, 1024 tokens y prompt de código. Muestra tiempo total, tokens generados, tokens/segundo aproximados, RAM del sistema, RSS de `llama-server` y carga CPU antes/después.

```bash
sudo ./scripts/benchmark.sh
```

Para probar un cliente remoto:

```bash
QWEN_BASE_URL="http://SERVER_IP:8080/v1" \
QWEN_API_KEY="API_KEY" \
sudo -E ./scripts/benchmark.sh
```

En otra terminal:

```bash
htop
journalctl -u qwen-coder -f
```

El valor de tokens/segundo depende de la CPU, afinidad, temperatura, versión de llama.cpp y prompt. OpenBLAS suele ayudar especialmente al procesamiento del prompt; no garantiza una mejora equivalente en la generación token a token.

## 15. Actualización de llama.cpp

Haz la actualización de forma controlada y conserva el servicio parado durante la recompilación:

```bash
sudo systemctl stop qwen-coder
sudo git -C /opt/qwen-coder/llama.cpp pull --ff-only
sudo cmake -S /opt/qwen-coder/llama.cpp \
  -B /opt/qwen-coder/llama.cpp/build \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_SERVER=ON \
  -DGGML_NATIVE=ON \
  -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=OpenBLAS
sudo cmake --build /opt/qwen-coder/llama.cpp/build \
  --config Release \
  --target llama-server llama-cli \
  --parallel "$(nproc)"
sudo systemctl start qwen-coder
sudo systemctl status qwen-coder --no-pager
```

El script de arranque ejecuta `llama-server --help` y valida los argumentos antes de iniciar. Si una actualización cambia una opción, el servicio quedará detenido con un error explícito en el journal en lugar de arrancar con una configuración desconocida.

## Afinación posterior

Mide un cambio cada vez. Para buscar el sweet spot real:

| Variable | Valores a probar |
| --- | --- |
| `LLAMA_THREADS` y `LLAMA_THREADS_BATCH` | `10`, `12` |
| `LLAMA_CONTEXT` | `4096`, `8192`, `16384` |
| `MODEL_QUANT` | `Q4_K_M`, `Q5_K_M` |

Después de cada cambio:

```bash
sudo systemctl restart qwen-coder
sudo ./scripts/benchmark.sh
```

La prioridad inicial es estabilidad, calidad, RAM razonable, latencia y finalmente throughput. Por eso `parallel=1`, `context=8192` y el modo CPU-only son los valores por defecto.

## Árbol del proyecto

```text
qwen-coder-server/
├── .env.example
├── .gitignore
├── CONTINUE_VSCODE.md
├── README.md
├── examples/
│   ├── client.mjs
│   ├── continue-config.yaml
│   └── client.py
├── scripts/
│   ├── benchmark.sh
│   ├── common.sh
│   ├── download-model.sh
│   ├── install-service.sh
│   ├── install.sh
│   ├── start.sh
│   ├── status.sh
│   └── stop.sh
└── systemd/
    └── qwen-coder.service
```

## QUICK START

Comandos completos desde un Ubuntu limpio:

```bash
git clone <REPO_URL> qwen-coder-server
cd qwen-coder-server

sudo ./scripts/install.sh
sudo ./scripts/download-model.sh
sudo cp .env.example /opt/qwen-coder/config/qwen-coder.env
sudo nano /opt/qwen-coder/config/qwen-coder.env
sudo ./scripts/install-service.sh
sudo systemctl enable --now qwen-coder

curl http://127.0.0.1:8080/health
```

Primera llamada OpenAI-compatible desde el servidor o desde un PC autorizado:

```bash
curl http://SERVER_IP:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer API_KEY" \
  -d '{
    "model": "qwen2.5-coder-14b",
    "messages": [{"role": "user", "content": "Escribe una función TypeScript que sume dos números."}],
    "temperature": 0.2,
    "max_tokens": 256
  }'
```
