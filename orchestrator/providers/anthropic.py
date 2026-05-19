"""
Anthropic (Claude) provider adapter.

Wraps the Anthropic Messages API so the agent loop can use Claude models
with streaming, vision, and full cost tracking.
"""

from __future__ import annotations

import logging
from typing import AsyncIterator

from orchestrator.providers import ChatMessage

try:
    from anthropic import Anthropic as AnthropicClient
    from anthropic.types import MessageParam

    _HAS_ANTHROPIC = True
except ImportError:  # pragma: no cover
    _HAS_ANTHROPIC = False

logger = logging.getLogger(__name__)


class AnthropicProvider:
    """Adapter for Anthropic's Claude API."""

    def __init__(
        self,
        api_key: str,
        model: str = "claude-sonnet-4-20250514",
        base_url: str | None = None,
    ) -> None:
        if not _HAS_ANTHROPIC:
            raise RuntimeError(
                "Anthropic SDK is not installed.  Run: pip install anthropic"
            )
        self.model = model
        self._client = AnthropicClient(api_key=api_key, base_url=base_url)

    async def chat(
        self,
        messages: list[ChatMessage],
        system: str | None = None,
        *,
        temperature: float = 0.7,
        max_tokens: int = 4096,
    ) -> str:
        """Send a non-streaming chat completion to Claude."""
        params: dict = {
            "model": self.model,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "messages": self._to_anthropic_messages(messages),
        }
        if system:
            params["system"] = system

        response = await self._async_maybe(
            self._client.messages.create(**params)  # type: ignore[arg-type]
        )
        return "".join(
            block.text if hasattr(block, "text") else ""
            for block in response.content
        )

    async def stream_chat(
        self,
        messages: list[ChatMessage],
        system: str | None = None,
        *,
        temperature: float = 0.7,
        max_tokens: int = 4096,
    ) -> AsyncIterator[str]:
        """Stream a chat completion from Claude token by token."""
        params: dict = {
            "model": self.model,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": True,
            "messages": self._to_anthropic_messages(messages),
        }
        if system:
            params["system"] = system

        stream = self._client.messages.create(**params)  # type: ignore[arg-type]
        async for event in await self._async_maybe(stream):  # type: ignore[union-attr]
            if hasattr(event, "delta") and hasattr(event.delta, "text"):
                yield event.delta.text

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _to_anthropic_messages(messages: list[ChatMessage]) -> list[MessageParam]:
        """Convert our generic ChatMessage list to Anthropic's format."""
        result: list[MessageParam] = []
        for msg in messages:
            result.append(
                MessageParam(role=msg.role, content=msg.content)  # type: ignore[typeddict-item]
            )
        return result

    @staticmethod
    async def _async_maybe(value: object) -> object:
        """If value is awaitable, await it; otherwise return as-is.

        The Anthropic sync client returns plain objects; the async client
        returns awaitables.  This helper lets us support both transparently.
        """
        if hasattr(value, "__await__"):
            return await value  # type: ignore[misc]
        return value