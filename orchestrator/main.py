"""FastAPI application for the Open Cowork orchestrator.

Exposes REST and WebSocket endpoints for task dispatch, status queries,
and real-time action streaming.  Keeps the orchestrator state in-memory
for v0.1; persistent storage will be wired in a later milestone.
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from orchestrator.agent_loop import AgentLoop, TaskState
from orchestrator.cost_tracker import CostTracker
from orchestrator.safety import SafetyGuard

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("orchestrator")

# ---------------------------------------------------------------------------
# In-memory stores (v0.1 – ephemeral)
# ---------------------------------------------------------------------------
_tasks: dict[str, TaskState] = {}
_cost_tracker = CostTracker()
_safety = SafetyGuard()


# ---------------------------------------------------------------------------
# FastAPI lifespan
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):  # noqa: D401
    """Startup / shutdown hook."""
    logger.info("Orchestrator starting up …")
    yield
    logger.info("Orchestrator shutting down …")


app = FastAPI(
    title="Open Cowork Orchestrator",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# REST endpoints
# ---------------------------------------------------------------------------
@app.post("/task")
async def create_task(payload: dict[str, Any]) -> dict[str, Any]:
    """Enqueue a new desktop-automation task.

    Body (JSON):
        {
            "instruction": "Open Safari and search for ...",
            "model": "claude-sonnet-4",   # optional
            "provider": "anthropic",       # optional
        }

    Returns:
        { "task_id": "<uuid>", "status": "queued" }
    """
    task_id = str(uuid.uuid4())
    instruction = payload.get("instruction", "")
    model = payload.get("model")
    provider = payload.get("provider")

    state = TaskState(
        task_id=task_id,
        instruction=instruction,
        model=model,
        provider=provider,
        status="queued",
    )
    _tasks[task_id] = state

    # Kick off the agent loop asynchronously.
    asyncio.create_task(
        AgentLoop.run(
            task_id=task_id,
            state=state,
            tracker=_cost_tracker,
            guard=_safety,
        )
    )

    logger.info("Task %s created: %r", task_id, instruction)
    return {"task_id": task_id, "status": "queued"}


@app.get("/status/{task_id}")
async def get_status(task_id: str) -> dict[str, Any]:
    """Return the current state of a task."""
    state = _tasks.get(task_id)
    if state is None:
        return {"task_id": task_id, "status": "unknown"}
    return {
        "task_id": state.task_id,
        "status": state.status,
        "instruction": state.instruction,
        "model": state.model,
        "provider": state.provider,
        "cost_usd": _cost_tracker.get_cost(task_id),
    }


# ---------------------------------------------------------------------------
# WebSocket endpoint
# ---------------------------------------------------------------------------
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    """Stream real-time task events to connected clients.

    Clients receive JSON messages shaped like:
        { "event": "action", "task_id": "...", "data": {...} }
        { "event": "cost_update", "task_id": "...", "usd": 0.0012 }
        { "event": "status_change", "task_id": "...", "status": "running" }
    """
    await websocket.accept()
    logger.info("WebSocket client connected")
    try:
        while True:
            # In v0.1 we simply echo back a heartbeat; the agent loop
            # will push events through a shared queue in a future rev.
            message = await websocket.receive_text()
            data = json.loads(message)
            await websocket.send_json({"echo": data})
    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected")
    except Exception as exc:  # pragma: no cover
        logger.exception("WebSocket error: %s", exc)
