"""Dummy Anthropic provider stub.

Provides an async ``complete`` method returning a placeholder response.
"""

import asyncio

class AnthropicProvider:
    async def complete(self, prompt: str) -> str:
        await asyncio.sleep(0.1)
        return f"[Anthropic dummy response to: {prompt}]"
