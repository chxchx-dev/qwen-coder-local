#!/usr/bin/env python3
"""Minimal OpenAI-compatible client for qwen-coder-server."""

import os

from openai import OpenAI


def required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise SystemExit(f"Falta la variable de entorno {name}.")
    return value


base_url = required_env("QWEN_BASE_URL").rstrip("/")
api_key = required_env("QWEN_API_KEY")
model = os.getenv("QWEN_MODEL", "qwen2.5-coder-14b")

client = OpenAI(base_url=base_url, api_key=api_key)
response = client.chat.completions.create(
    model=model,
    messages=[
        {
            "role": "system",
            "content": "You are an expert software engineering assistant.",
        },
        {
            "role": "user",
            "content": "Create a TypeScript function that validates an email address.",
        },
    ],
    temperature=0.2,
    max_tokens=1024,
)

print(response.choices[0].message.content or "")
