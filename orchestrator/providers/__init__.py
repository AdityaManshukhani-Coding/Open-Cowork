"""
Provider adapters for AI model back-ends.

Each module in this package implements a thin adapter over a model provider's
API (Anthropic, OpenAI, Ollama, etc.).  Adapters follow a common protocol so
the agent loop can dispatch tasks to any provider transparently.
"""

from __future__ import annotations

from typing import Protocol, AsyncIterator


class ProviderConfig(Protocol):
    """Minimal provider configuration protocol."""

    api_key: str | None
    model: str
    base_url: str | None


class ChatMessage:
    """A single message in a chat conversation."""

    def __init__(self, role: str, content: str) -> None:
        self.role = role
        self.content = content

    def to_dict(self) -> dict[str, str]:
        return {"role": self.role, "content": self.content}


class ProviderAdapter(Protocol):
    """Interface every provider adapter MUST satisfy."""

    async def chat(
        self,
        messages: list[ChatMessage],
        system: str | None = None,
        *,
        temperature: float = 0.7,
        max_tokens: int = 4096,
    ) -> str:
        """Send a chat completion request and return the reply text."""
        ...

    async def stream_chat(
        self,
        messages: list[ChatMessage],
        system: str | None = None,
        *,
        temperature: float = 0.7,
        max_tokens: int = 4096,
    ) -> AsyncIterator[str]:
        """Send a streaming chat request and yield tokens as they arrive."""
        ...
        yield  # pragma: no cover


__all__ = [
    "ProviderConfig",
    "ProviderAdapter",
    "ChatMessage",
]