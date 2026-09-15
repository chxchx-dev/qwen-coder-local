# Pruebas de la API con `curl`

La API del servidor es el núcleo compartido para los MVPs de este repositorio. Estas pruebas sirven para verificar primero la infraestructura y después la generación del modelo.

## Variables

En el mismo equipo donde corre el servidor:

```bash
SERVER_URL="http://127.0.0.1:8080"
API_KEY="EL_VALOR_DE_LLAMA_API_KEY"
MODEL="qwen2.5-coder-14b"
```

Desde otro equipo, cambia `SERVER_URL` por la IP del servidor o por su IP privada de Tailscale/WireGuard:

```bash
SERVER_URL="http://IP_DEL_SERVIDOR:8080"
```

La base OpenAI-compatible siempre es `${SERVER_URL}/v1`.

## 1. Health check

Este endpoint no necesita API key:

```bash
curl -i "${SERVER_URL}/health"
```

Resultado esperado cuando el modelo está listo:

```text
HTTP/1.1 200 OK
{"status":"ok"}
```

Un `503` durante la carga inicial es normal.

## 2. Ver los modelos disponibles

```bash
curl -sS "${SERVER_URL}/v1/models" \
  -H "Authorization: Bearer ${API_KEY}"
```

Debe aparecer el alias:

```text
qwen2.5-coder-14b
```

## 3. Primera prueba de chat

```bash
curl -sS "${SERVER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d @- <<JSON
{
  "model": "${MODEL}",
  "messages": [
    {
      "role": "system",
      "content": "Eres un asistente de ingeniería de software. Responde en español y de forma breve."
    },
    {
      "role": "user",
      "content": "Propón tres MVPs pequeños que podamos construir sobre esta API local."
    }
  ],
  "temperature": 0.2,
  "max_tokens": 256,
  "stream": false
}
JSON
```

## 4. Prueba de generación de código

```bash
curl -sS "${SERVER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d @- <<JSON
{
  "model": "${MODEL}",
  "messages": [
    {
      "role": "user",
      "content": "Escribe una función TypeScript que valide un email y agrega tres pruebas unitarias. Devuelve solo el código."
    }
  ],
  "temperature": 0.1,
  "max_tokens": 512,
  "stream": false
}
JSON
```

## 5. Prueba con streaming

```bash
curl -N "${SERVER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d @- <<JSON
{
  "model": "${MODEL}",
  "messages": [
    {
      "role": "user",
      "content": "Explica en cinco puntos cómo probar un MVP antes de publicarlo."
    }
  ],
  "temperature": 0.2,
  "max_tokens": 256,
  "stream": true
}
JSON
```

## 6. Comprobar que la autenticación funciona

Esta llamada debe responder `401`:

```bash
curl -i "${SERVER_URL}/v1/models" \
  -H "Authorization: Bearer clave-incorrecta"
```

No incluyas una API key real en archivos versionados, capturas ni historiales compartidos.

## URLs rápidas

Sustituye `127.0.0.1` por la IP del servidor si haces la prueba remotamente:

| Uso | URL |
| --- | --- |
| Estado del servidor | `http://127.0.0.1:8080/health` |
| Modelos | `http://127.0.0.1:8080/v1/models` |
| Chat | `http://127.0.0.1:8080/v1/chat/completions` |

## Pruebas de un MVP

Cada MVP debe llamar al modelo desde su backend usando `/v1/chat/completions`. El navegador no debe conocer `LLAMA_API_KEY`. Para cada MVP conviene mantener:

- un `README.md` con su URL y variables de entorno;
- una prueba de health propia;
- pruebas de respuestas válidas y errores;
- prompts versionados sin secretos;
- un puerto o ruta claramente documentado.

El benchmark general del servidor sigue disponible en:

```bash
sudo ./scripts/benchmark.sh
```
