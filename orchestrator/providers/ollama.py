"""Ollama provider adapter for Open Cowork.

Wraps the local Ollama HTTP API (default ``http://localhost:11434``) and
exposes a single async ``generate()`` helper that the agent loop can call
without knowing which backend is in use.
"""

from __future__ import annotations

import logging
import os
from typing import Any

logger = logging.getLogger(__name__)


class OllamaProvider:
    """Adapter for the local Ollama API."""

    def __init__(self, base_url: str | None = None) -> None:
        """Initialise the provider with an optional custom base URL.

        Args:
            base_url: Ollama server URL.  Falls back to the
                ``OLLAMA_BASE_URL`` environment variable or
                ``http://localhost:11434``.
        """
        self._base_url = base_url or os.getenv(
            "OLLAMA_BASE_URL", "http://localhost:11434"
        )

    async def generate(self, prompt: str, *, model: str = "llama3") -> dict[str, Any]:
        """Send *prompt* to the local Ollama server and return the raw response.

        Args:
            prompt: User instruction text.
            model: Ollama model tag (default ``llama3``).

        Returns:
            Dictionary with at least ``content`` and ``usage`` keys.
        """
        # TODO(v0.2): implement real HTTP call via httpx/aiohttp.
        logger.info("Ollama generate() called with model=%s", model)
        return {
            "content": "",
            "usage": {"prompt_tokens": 0, "completion_tokens": 0},
        }
