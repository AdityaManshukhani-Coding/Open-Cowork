"""
Ollama (local) provider adapter.

Wraps the Ollama API so the agent loop can use locally-hosted models
via the Ollama HTTP endpoint (default http://localhost:11434/api/chat).
All inference is free since it runs on the user's own hardware.
"""

from __future__ import annotations

import json
import logging
from typing import AsyncIterator

import httpx

from orchestrator.providers import ChatMessage

logger = logging.getLogger(__name__)

_DEFAULT_BASE_URL = "http://localhost:11434"


class OllamaProvider:
    """Adapter for locally-hosted Ollama models."""

    def __init__(
        self,
        api_key: str | None = None,
        model: str = "llama3.2",
        base_url: str | None = None,
    ) -> None:
        # Ollama does not require an API key.
        _ = api_key
        self.model = model
        self.base_url = (base_url or _DEFAULT_BASE_URL).rstrip("/")

    async def chat(
        self,
        messages: list[ChatMessage],
        system: str | None = None,
        *,
        temperature: float = 0.7,
        max_tokens: int = 4096,
    ) -> str:
        """Send a non-streaming chat completion to Ollama."""
        ollama_messages = self._to_ollama_messages(messages, system=system)
        payload = {
            "model": self.model,
            "messages": ollama_messages,
            "options": {
                "temperature": temperature,
                "num_predict": max_tokens,
            },
            "stream": False,
        }

        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                f"{self.base_url}/api/chat",
                json=payload,
            )
            response.raise_for_status()
            data = response.json()

        return data.get("message", {}).get("content", "")

    async def stream_chat(
        self,
        messages: list[ChatMessage],
        system: str | None = None,
        *,
        temperature: float = 0.7,
        max_tokens: int = 4096,
    ) -> AsyncIterator[str]:
        """Stream a chat completion from Ollama token by token."""
        ollama_messages = self._to_ollama_messages(messages, system=system)
        payload = {
            "model": self.model,
            "messages": ollama_messages,
            "options": {
                "temperature": temperature,
                "num_predict": max_tokens,
            },
            "stream": True,
        }

        async with httpx.AsyncClient(timeout=300.0) as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/api/chat",
                json=payload,
            ) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line.strip():
                        continue
                    try:
                        chunk = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    content = chunk.get("message", {}).get("content", "")
                    if content:
                        yield content
                    if chunk.get("done", False):
                        break

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _to_ollama_messages(
        messages: list[ChatMessage],
        system: str | None = None,
    ) -> list[dict[str, str]]:
        """Convert to Ollama's message format, optionally including a
        system message as the first entry."""
        result: list[dict[str, str]] = []
        if system:
            result.append({"role": "system", "content": system})
        for msg in messages:
            result.append(msg.to_dict())
        return result