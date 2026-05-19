"""Agent loop placeholder.

Manages the lifecycle of a single task: invokes the LLM provider, streams
updates to registered WebSocket connections, and updates task status in
storage. The real implementation will be expanded later.
"""

import asyncio
from typing import Dict, List
from fastapi import WebSocket

from .storage import TaskStorage
from .providers.openai import generate as openai_generate

class AgentLoop:
    """Simple orchestrator for a single task.

    For each task we keep a list of WebSocket connections that should receive
    streamed events. The ``start_task`` method launches an async background task
    that calls the LLM provider and pushes messages.
    """

    def __init__(self, storage: TaskStorage):
        self.storage = storage
        self._ws_map: Dict[str, List[WebSocket]] = {}
        self._running_tasks: Dict[str, asyncio.Task] = {}

    async def register_ws(self, task_id: str, ws: WebSocket) -> None:
        """Register a websocket to receive updates for *task_id*."""
        self._ws_map.setdefault(task_id, []).append(ws)
        # Send current status immediately.
        task = await self.storage.get_task(task_id)
        if task:
            await ws.send_json({"event": "status", "data": task.get("status")})

    async def unregister_ws(self, task_id: str, ws: WebSocket) -> None:
        """Remove a websocket from the notification list."""
        if task_id in self._ws_map:
            try:
                self._ws_map[task_id].remove(ws)
            except ValueError:
                pass
            if not self._ws_map[task_id]:
                del self._ws_map[task_id]

    def start_task(self, task_id: str, prompt: str) -> None:
        """Kick off the background coroutine for a task.

        The coroutine updates storage status, calls the LLM provider and streams
        results to any registered websockets.
        """
        if task_id in self._running_tasks:
            # Task already running – ignore duplicate start.
            return
        loop = asyncio.get_event_loop()
        self._running_tasks[task_id] = loop.create_task(self._run(task_id, prompt))

    async def _run(self, task_id: str, prompt: str) -> None:
        """Internal coroutine that drives a single task lifecycle."""
        await self.storage.update_task(task_id, {"status": "running"})
        await self._broadcast(task_id, {"event": "status", "data": "running"})
        try:
            # Call the LLM provider – placeholder uses OpenAI wrapper.
            response = await openai_generate(prompt)
            await self.storage.update_task(task_id, {"status": "completed", "result": response})
            await self._broadcast(task_id, {"event": "result", "data": response})
        except Exception as exc:
            await self.storage.update_task(task_id, {"status": "error", "error": str(exc)})
            await self._broadcast(task_id, {"event": "error", "data": str(exc)})
        finally:
            # Clean up task record.
            self._running_tasks.pop(task_id, None)

    async def _broadcast(self, task_id: str, message: dict) -> None:
        """Send *message* to all websockets registered for *task_id*."""
        for ws in self._ws_map.get(task_id, []):
            try:
                await ws.send_json(message)
            except Exception:
                # Silently ignore broken connections – they will be cleaned up on next recv.
                pass
