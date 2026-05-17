"""OpenAI provider adapter for Open Cowork.

Wraps the OpenAI Chat Completions API and exposes a single async
``generate()`` helper that the agent loop can consume.
"""

from __future__ import annotations

import logging
import os
from typing import Any

logger = logging.getLogger(__name__)


class OpenAIProvider:
    """Adapter for the OpenAI Chat Completions API."""

    def __init__(self, api_key: str | None = None) -> None:
        """Initialise the provider with an optional API key.

        Args:
            api_key: OpenAI API key.  Falls back to the
                ``OPENAI_API_KEY`` environment variable.
        """
        self._api_key = api_key or os.getenv("OPENAI_API_KEY")
        if not self._api_key:
            logger.warning("OpenAI API key not provided")

    async def generate(self, prompt: str, *, model: str = "gpt-4o") -> dict[str, Any]:
        """Send *prompt* to the OpenAI API and return the raw response.

        Args:
            prompt: User instruction text.
            model: Model identifier (default: gpt-4o).

        Returns:
            Dictionary with at least ``content`` and ``usage`` keys.
        """
        # TODO(v0.2): implement real HTTP call via httpx/aiohttp.
        logger.info("OpenAI generate() called with model=%s", model)
        return {
            "content": "",
            "usage": {"prompt_tokens": 0, "completion_tokens": 0},
        }
