# Conectar VS Code con Continue a este laboratorio Qwen

Esta guía conecta Continue con la instalación real de `qwen-coder` que está funcionando en este servidor.

## Datos de esta instalación

```text
Servidor: 157.173.207.46
Puerto: 8090
Modelo: qwen2.5-coder-14b
API base: /v1
```

El servidor ya está levantado y responde correctamente en el puerto `8090`. El puerto `8080` pertenece a otro servicio y no debe usarse para Qwen.

## Opción recomendada: túnel SSH

Si VS Code está en tu PC y el servidor está en Internet, usa un túnel SSH. Así Continue se conecta a `localhost` y la API key viaja dentro de SSH.

### 1. Abrir el túnel

Desde una terminal de tu PC, mantenla abierta mientras uses Continue:

```bash
ssh -N -L 8090:127.0.0.1:8090 USUARIO_SSH@157.173.207.46
```

Reemplaza `USUARIO_SSH` por tu usuario real del servidor. Si el SSH usa otro puerto:

```bash
ssh -p PUERTO_SSH -N -L 8090:127.0.0.1:8090 USUARIO_SSH@157.173.207.46
```

No cierres esa terminal. Para comprobar el túnel desde tu PC:

```bash
curl -i http://127.0.0.1:8090/health
```

Debe devolver:

```text
HTTP/1.1 200 OK
{"status":"ok"}
```

Con el túnel abierto, Continue usará esta URL:

```text
http://127.0.0.1:8090/v1
```

## Alternativa: conexión directa

También puedes conectarte directamente usando:

```text
http://157.173.207.46:8090/v1
```

Úsala únicamente desde una red confiable o mediante Tailscale/WireGuard. Es una conexión HTTP sin TLS; para Internet pública es preferible el túnel SSH.

## 1. Obtener la API key

La API key se encuentra solo en el servidor, en:

```text
/opt/qwen-coder/config/qwen-coder.env
```

Conéctate por SSH al servidor y ejecuta:

```bash
sudo awk -F= '$1=="LLAMA_API_KEY" {print $2}' /opt/qwen-coder/config/qwen-coder.env
```

Copia el valor de la salida. No lo publiques, no lo guardes en Git y no lo pegues en este chat.

## 2. Instalar Continue en VS Code

En tu PC:

1. Abre VS Code.
2. Pulsa `Ctrl+Shift+X` para abrir Extensions.
3. Busca `Continue - open-source AI code agent`.
4. Instala la extensión oficial de Continue.
5. Abre Continue desde el icono de la barra lateral.

## 3. Crear el archivo secreto de Continue

Continue no recibe automáticamente un `export` de tu terminal cuando se ejecuta como extensión de VS Code. Debes guardar la clave en un archivo `.env` local.

La opción más sencilla para este proyecto es crear:

```text
<carpeta-del-proyecto>/.continue/.env
```

Contenido:

```dotenv
QWEN_API_KEY=PEGA_AQUI_LA_API_KEY_DEL_SERVIDOR
```

No pongas comillas. El `.gitignore` de este repositorio ya ignora los archivos `.env`.

También puedes usar un archivo global:

- Linux/macOS: `~/.continue/.env`
- Windows: `%USERPROFILE%\.continue\.env`

## 4. Abrir la configuración de Continue

1. Abre el panel de Continue.
2. Abre el selector de configuración/modelo que aparece encima del chat.
3. Pulsa el icono de engranaje junto a `Local Config`.
4. Se abrirá el archivo `config.yaml`.
5. Reemplaza su contenido por la configuración del siguiente paso.

La ubicación habitual del archivo es:

- Linux/macOS: `~/.continue/config.yaml`
- Windows: `%USERPROFILE%\.continue\config.yaml`

## 5. Pegar la configuración del modelo

### Si usas el túnel SSH

Usa `127.0.0.1`:

```yaml
name: Qwen Coder laboratorio
version: 0.0.1
schema: v1

models:
  - name: Qwen2.5 Coder 14B - laboratorio
    provider: openai
    model: qwen2.5-coder-14b
    apiBase: http://127.0.0.1:8090/v1
    apiKey: ${{ secrets.QWEN_API_KEY }}
    contextLength: 8192
    useResponsesApi: false
    roles:
      - chat
      - edit
      - apply
    defaultCompletionOptions:
      temperature: 0.2
      maxTokens: 1024
```

### Si usas conexión directa

Cambia únicamente `apiBase` por:

```yaml
apiBase: http://157.173.207.46:8090/v1
```

El resto de la configuración permanece igual.

También puedes usar el archivo preparado [examples/continue-config.yaml](examples/continue-config.yaml) como referencia.

## 6. Guardar y recargar Continue

1. Guarda `config.yaml`.
2. En el selector de Continue, pulsa `Reload config` si aparece.
3. Selecciona `Qwen2.5 Coder 14B - laboratorio`.
4. Si Continue no detecta el cambio, abre la paleta de comandos de VS Code con `Ctrl+Shift+P`.
5. Ejecuta `Developer: Reload Window`.

Si modificaste `.env`, reinicia VS Code para que Continue vuelva a leer el secreto.

## 7. Probar la conexión antes de usar el chat

Con túnel SSH:

```bash
export SERVER_URL="http://127.0.0.1:8090"
```

Con conexión directa:

```bash
export SERVER_URL="http://157.173.207.46:8090"
```

Comprueba el servidor:

```bash
curl -i "$SERVER_URL/health"
```

Comprueba el modelo usando la misma API key que pusiste en `.continue/.env`:

```bash
export API_KEY="TU_API_KEY"

curl -sS "$SERVER_URL/v1/models" \
  -H "Authorization: Bearer $API_KEY"
```

Debe aparecer `qwen2.5-coder-14b`.

## 8. Primera prueba dentro de Continue

En el chat de Continue escribe:

```text
Escribe una función Python llamada suma(a, b), agrega tipos y crea tres pruebas unitarias. Explícalo brevemente.
```

Para editar código:

1. Selecciona una función en VS Code.
2. Abre Continue.
3. Pide un cambio concreto, por ejemplo: `Refactoriza esta función y agrega manejo de errores.`
4. Revisa el diff antes de aceptar la modificación.

El modelo está configurado para `chat`, `edit` y `apply`. La autocompletación carácter a carácter puede ser lenta porque este laboratorio usa CPU-only.

## Solución de problemas

- `401 Invalid API Key`: revisa que `QWEN_API_KEY` sea exactamente la clave de `/opt/qwen-coder/config/qwen-coder.env`.
- `404`: confirma que `apiBase` termine exactamente en `/v1`.
- `Connection refused`: abre el túnel SSH o comprueba que `qwen-coder` esté activo.
- `fetch failed`: prueba primero el `curl` de `/health` desde el mismo equipo donde corre VS Code.
- El modelo no aparece: revisa que el valor sea exactamente `qwen2.5-coder-14b`.

Desde el servidor puedes revisar el servicio con:

```bash
sudo systemctl status qwen-coder --no-pager
sudo journalctl -u qwen-coder -n 80 --no-pager
```

Documentación oficial de Continue:

- [Proveedor OpenAI y endpoints compatibles](https://docs.continue.dev/customize/model-providers/top-level/openai)
- [Secretos y archivos `.env`](https://docs.continue.dev/faqs)
- [Configuración local en VS Code](https://docs.continue.dev/customize/deep-dives/configuration)
