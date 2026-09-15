# Usar qwen-coder-local desde VS Code con Continue

Esta guía conecta la extensión [Continue](https://www.continue.dev/) de VS Code con este servidor local OpenAI-compatible.

## 1. Requisitos

El servidor debe estar instalado, tener el modelo descargado y estar iniciado.

Desde el servidor, comprueba que está listo:

```bash
curl http://127.0.0.1:8080/health
```

Debe devolver HTTP 200 y `{"status":"ok"}`. Durante la carga inicial puede devolver HTTP 503.

Si VS Code se ejecuta en el mismo equipo que el servidor, usa:

```text
http://127.0.0.1:8080/v1
```

Si VS Code está en otro equipo, usa la IP del servidor o, preferiblemente, la IP privada de Tailscale/WireGuard:

```text
http://IP_DEL_SERVIDOR:8080/v1
```

La URL debe terminar en `/v1`.

## 2. Instalar Continue en VS Code

1. Abre VS Code.
2. Abre Extensions (`Ctrl+Shift+X`).
3. Busca e instala **Continue - open-source AI code agent**.
4. Abre el panel de Continue desde la barra lateral.

## 3. Crear el secreto local

La API key debe ser exactamente la misma que `LLAMA_API_KEY` en:

```text
/opt/qwen-coder/config/qwen-coder.env
```

Para mantenerla fuera del repositorio, crea el archivo global de secretos de Continue:

- Linux/macOS: `~/.continue/.env`
- Windows: `%USERPROFILE%\\.continue\\.env`

Contenido:

```dotenv
QWEN_API_KEY=PEGA_AQUI_EL_VALOR_DE_LLAMA_API_KEY
```

No pongas comillas y no subas este archivo a Git. Continue también admite `<workspace>/.continue/.env` si quieres guardar el secreto solo para un proyecto.

## 4. Configurar el modelo

En Continue, abre el selector de configuración, pulsa el icono de engranaje de la configuración local y edita `config.yaml`.

También puedes copiar [examples/continue-config.yaml](examples/continue-config.yaml) a la configuración local y cambiar `IP_DEL_SERVIDOR` por la dirección correcta.

La configuración mínima es:

```yaml
name: Qwen Coder local
version: 0.0.1
schema: v1

models:
  - name: Qwen2.5 Coder 14B local
    provider: openai
    model: qwen2.5-coder-14b
    apiBase: http://IP_DEL_SERVIDOR:8080/v1
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

Si VS Code y el servidor están en el mismo equipo, cambia `IP_DEL_SERVIDOR` por `127.0.0.1`. El nombre del modelo debe ser exactamente `qwen2.5-coder-14b`, que es el alias configurado por `scripts/start.sh`.

Después de guardar, selecciona **Reload config** en Continue. Si no aparece, recarga la ventana de VS Code (`Developer: Reload Window`).

## 5. Uso diario

- **Chat:** abre el panel de Continue y pregunta por el código del proyecto.
- **Edición:** selecciona código y pide un cambio concreto; revisa la propuesta antes de aplicarla.
- **Apply/Agent:** úsalo para cambios que afecten varios archivos y revisa cada diff antes de aceptar.

Este modelo está configurado inicialmente para `chat`, `edit` y `apply`. En una máquina CPU-only de 12 cores, la autocompletación carácter a carácter puede resultar lenta; se recomienda empezar con Chat y edición bajo demanda.

## 6. Verificación y solución de problemas

Prueba primero desde el equipo donde corre VS Code:

```bash
curl http://IP_DEL_SERVIDOR:8080/v1/models \
  -H "Authorization: Bearer PEGA_AQUI_EL_VALOR_DE_LLAMA_API_KEY"
```

- `401`: la clave de Continue no coincide con `LLAMA_API_KEY`.
- `404`: revisa que `apiBase` termine en `/v1` y que el modelo sea `qwen2.5-coder-14b`.
- `Connection refused` o timeout: revisa que el servicio esté iniciado, el puerto 8080, UFW y la VPN/ruta de red.
- `503` en `/health`: el modelo aún está cargando o el servicio falló. Consulta `sudo journalctl -u qwen-coder -n 80 --no-pager`.

No abras el puerto 8080 a Internet sin limitar el firewall. Tailscale o WireGuard es la opción recomendada para acceder desde otro equipo.

## Rutas de configuración de Continue

Según el sistema operativo, la configuración local suele estar en:

- Linux/macOS: `~/.continue/config.yaml`
- Windows: `%USERPROFILE%\\.continue\\config.yaml`

La extensión también permite abrirla desde el selector de configuración y el icono de engranaje.

Documentación oficial:

- [Configurar modelos OpenAI y proveedores OpenAI-compatible](https://docs.continue.dev/customize/model-providers/top-level/openai)
- [Secretos y archivos `.env` en Continue](https://docs.continue.dev/faqs)
- [Configuración de Continue en VS Code](https://docs.continue.dev/customize/deep-dives/configuration)
