# MVPs

Esta carpeta contiene los productos y experimentos que construyamos sobre `qwen-coder-local`.

La infraestructura del modelo vive fuera de esta carpeta. Cada MVP debe ser autónomo y documentar cómo se ejecuta, qué variables necesita y cómo se prueba.

Estructura recomendada:

```text
mvps/
└── nombre-del-mvp/
    ├── README.md
    ├── .env.example
    ├── src/
    └── tests/
```

Reglas básicas:

- El backend del MVP usa la API OpenAI-compatible en `/v1`.
- Ningún frontend recibe `LLAMA_API_KEY`.
- Las claves y archivos `.env` no se versionan.
- Cada MVP incluye una prueba reproducible y un ejemplo de uso.
- Los cambios de infraestructura se mantienen en `scripts/`, `systemd/` y la documentación raíz.

Consulta [API_TESTING.md](../API_TESTING.md) para probar el servidor antes de probar un MVP.
