"""
OpenAI (GPT) provider adapter.

Wraps the OpenAI Chat Completions API so the agent loop can use GPT models
with streaming, vision, and full cost tracking.
"""

from __future__ import annotations

import logging
from typing import AsyncIterator

from openai import AsyncOpenAI

from orchestrator.providers import ChatMessage

logger = logging.getLogger(__name__)


class OpenAIProvider:
    """Adapter for OpenAI's GPT API."""

    def __init__(
        self,
        api_key: str,
        model: str = "gpt-4o",
        base_url: str | None = None,
    ) -> None:
        self.model = model
        self._client = AsyncOpenAI(api_key=api_key, base_url=base_url)

    async def chat(
        self,
        messages: list[ChatMessage],
        system: str | None = None,
        *,
        temperature: float = 0.7,
        max_tokens: int = 4096,
    ) -> str:
        """Send a non-streaming chat completion to GPT."""
        openai_messages = self._to_openai_messages(messages, system=system)
        response = await self._client.chat.completions.create(
            model=self.model,
            messages=openai_messages,  # type: ignore[arg-type]
            temperature=temperature,
            max_tokens=max_tokens,
            stream=False,
        )
        choice = response.choices[0]
        text = choice.message.content or ""
        return text

    async def stream_chat(
        self,
        messages: list[ChatMessage],
        system: str | None = None,
        *,
        temperature: float = 0.7,
        max_tokens: int = 4096,
    ) -> AsyncIterator[str]:
        """Stream a chat completion from GPT token by token."""
        openai_messages = self._to_openai_messages(messages, system=system)
        stream = await self._client.chat.completions.create(
            model=self.model,
            messages=openai_messages,  # type: ignore[arg-type]
            temperature=temperature,
            max_tokens=max_tokens,
            stream=True,
        )
        async for chunk in stream:  # type: ignore[arg-type]
            delta = chunk.choices[0].delta if chunk.choices else None
            if delta and delta.content:
                yield delta.content

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _to_openai_messages(
        messages: list[ChatMessage],
        system: str | None = None,
    ) -> list[dict[str, str]]:
        """Convert to OpenAI's message format, optionally prepending a
        system message."""
        result: list[dict[str, str]] = []
        if system:
            result.append({"role": "system", "content": system})
        for msg in messages:
            result.append(msg.to_dict())
        return result