"""Background agent loop for the orchestrator.

Continuously polls the storage layer for pending tasks, processes them using a
placeholder LLM provider, and records results. This is a minimal stub for the
v0.1 foundation.
"""

import asyncio
from . import storage, safety, providers
from .cost_tracker import CostTracker

cost_tracker = CostTracker()

async def _process(task_id: str, prompt: str):
    """Process a single task.

    Performs a safety check, calls a dummy provider, updates cost tracking, and
    stores the result.
    """
    if not safety.check_allowed_prompt(prompt):
        await storage.update_status(task_id, "rejected")
        return
    provider = providers.openai.OpenAIProvider()
    response = await provider.complete(prompt)
    cost_tracker.add_usage(tokens=10, cost=0.001)
    await storage.save_result(task_id, response)
    await storage.update_status(task_id, "completed")

async def run():
    """Main loop started at FastAPI startup.

    Polls for pending tasks every few seconds.
    """
    while True:
        pending = await storage.fetch_pending()
        if pending:
            for t in pending:
                await _process(t["task_id"], t["prompt"])
        else:
            await asyncio.sleep(2)

