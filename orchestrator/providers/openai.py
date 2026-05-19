"""Dummy OpenAI provider stub.

Implements a minimal async ``complete`` method that pretends to call the real
OpenAI API but simply returns a canned response after a short sleep.
"""

import asyncio

class OpenAIProvider:
    async def complete(self, prompt: str) -> str:
        await asyncio.sleep(0.1)
        return f"[OpenAI dummy response to: {prompt}]"
