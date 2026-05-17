"""Anthropic (Claude) provider adapter for Open Cowork.

Wraps the Anthropic Messages API and exposes a single async
``generate()`` helper that the agent loop can consume.
"""

from __future__ import annotations

import logging
import os
from typing import Any

logger = logging.getLogger(__name__)


class AnthropicProvider:
    """Adapter for the Anthropic Messages API."""

    def __init__(self, api_key: str | None = None) -> None:
        """Initialise the provider with an optional API key.

        Args:
            api_key: Anthropic API key.  Falls back to the
                ``ANTHROPIC_API_KEY`` environment variable.
        """
        self._api_key = api_key or os.getenv("ANTHROPIC_API_KEY")
        if not self._api_key:
            logger.warning("Anthropic API key not provided")

    async def generate(self, prompt: str, *, model: str = "claude-sonnet-4-20250514") -> dict[str, Any]:
        """Send *prompt* to Claude and return the raw response.

        Args:
            prompt: User instruction text.
            model: Model identifier (default: latest Sonnet).

        Returns:
            Dictionary with at least ``content`` and ``usage`` keys.
        """
        # TODO(v0.2): implement real HTTP call via httpx/aiohttp.
        logger.info("Anthropic generate() called with model=%s", model)
        return {
            "content": "",
            "usage": {"prompt_tokens": 0, "completion_tokens": 0},
        }
