"""Dummy Ollama provider stub.

Implements an async ``complete`` method that returns a canned response.
"""

import asyncio

class OllamaProvider:
    async def complete(self, prompt: str) -> str:
        await asyncio.sleep(0.1)
        return f"[Ollama dummy response to: {prompt}]"
