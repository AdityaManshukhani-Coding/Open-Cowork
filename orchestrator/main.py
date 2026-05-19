"""
FastAPI application for the Open Cowork agent orchestrator.

Exposes:
  - POST /task        -- create and launch a new agent task
  - GET  /status/{id} -- query task status
  - WS   /ws/{id}     -- stream progress updates over WebSocket
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from orchestrator.agent_loop import AgentLoop, TaskStatus
from orchestrator.cost_tracker import CostTracker
from orchestrator.safety import SafetyGate, SafetyMode
from orchestrator.storage import Storage, TaskRecord

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Globals (set during lifespan)
# ---------------------------------------------------------------------------

_storage: Storage | None = None
_safety: SafetyGate | None = None
_cost_tracker: CostTracker | None = None
_running_tasks: dict[str, AgentLoop] = {}

# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI) -> Any:
    """Initialise and tear down shared resources."""
    global _storage, _safety, _cost_tracker

    _storage = Storage()
    _storage.initialise_schema()
    _safety = SafetyGate(mode=SafetyMode.APPROVE_BEFORE_ACTION)
    _cost_tracker = CostTracker(budget_limit_usd=None)

    logger.info("Open Cowork orchestrator started")
    yield

    # Shutdown: cancel any running tasks
    for task_id, loop in list(_running_tasks.items()):
        await loop.cancel()
    _running_tasks.clear()

    if _storage is not None:
        _storage.close()

    logger.info("Open Cowork orchestrator shut down")


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Open Cowork Agent",
    version="0.1.0",
    description="AI desktop agent orchestrator for macOS",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class TaskRequest(BaseModel):
    """Request body for POST /task."""

    task: str = Field(..., min_length=1, description="Natural-language task description")
    model: str = Field(default="gpt-4o", description="AI model identifier")
    provider: str = Field(default="openai", description="Provider name (openai, anthropic, ollama)")
    safety_mode: str = Field(default="approve_before_action", description="Safety mode")


class TaskResponse(BaseModel):
    """Response returned by POST /task."""

    task_id: str
    status: str
    message: str


class StatusResponse(BaseModel):
    """Response returned by GET /status/{task_id}."""

    task_id: str
    status: str
    user_task: str
    cost_usd: float
    started_at: str | None = None
    finished_at: str | None = None


# ---------------------------------------------------------------------------
# Dependency helpers
# ---------------------------------------------------------------------------


def _get_storage() -> Storage:
    """Return the global storage instance."""
    if _storage is None:
        raise RuntimeError("Storage not initialised")
    return _storage


def _get_safety() -> SafetyGate:
    """Return the global safety gate instance."""
    if _safety is None:
        raise RuntimeError("Safety gate not initialised")
    return _safety


def _get_cost_tracker() -> CostTracker:
    """Return the global cost tracker instance."""
    if _cost_tracker is None:
        raise RuntimeError("Cost tracker not initialised")
    return _cost_tracker


# ---------------------------------------------------------------------------
# Provider factory
# ---------------------------------------------------------------------------


def _build_provider(provider_name: str, model: str) -> Any:
    """Build a provider adapter from its name and model string.

    In a real deployment the API key would come from settings/store.
    """
    if provider_name == "anthropic":
        from orchestrator.providers.anthropic import AnthropicProvider

        return AnthropicProvider(
            api_key="<set-me>",  # TODO: read from settings
            model=model,
        )
    elif provider_name == "openai":
        from orchestrator.providers.openai import OpenAIProvider

        return OpenAIProvider(
            api_key="<set-me>",  # TODO: read from settings
            model=model,
        )
    elif provider_name == "ollama":
        from orchestrator.providers.ollama import OllamaProvider

        return OllamaProvider(model=model)
    else:
        raise ValueError(f"Unknown provider: {provider_name}")


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.post("/task", response_model=TaskResponse, status_code=201)
async def create_task(body: TaskRequest) -> dict[str, str]:
    """Accept a natural-language task, create it, and launch the agent loop
    in the background."""
    if _storage is None:
        raise HTTPException(status_code=503, detail="Storage not initialised")

    task_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    # Persist initial record
    record = TaskRecord(
        task_id=task_id,
        user_task=body.task,
        status=TaskStatus.PENDING.value,
        started_at=now,
    )
    await _storage.save_task(record)

    # Build provider, safety gate, and agent loop
    try:
        provider = _build_provider(body.provider, body.model)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    safety_mode = SafetyMode(body.safety_mode)
    safety = SafetyGate(mode=safety_mode)
    cost_tracker = CostTracker()
    loop = AgentLoop(
        task_id=task_id,
        user_task=body.task,
        provider=provider,
        safety=safety,
        cost_tracker=cost_tracker,
        storage=_storage,
    )

    _running_tasks[task_id] = loop

    # Launch agent loop in the background
    asyncio.create_task(loop.run())

    logger.info("Task %s created: %s", task_id, body.task[:80])
    return {
        "task_id": task_id,
        "status": TaskStatus.PENDING.value,
        "message": "Task created and agent loop launched",
    }


@app.get("/status/{task_id}", response_model=StatusResponse)
async def get_task_status(task_id: str) -> dict[str, Any]:
    """Return the current status and cost for a given task."""
    storage = _get_storage()
    record = await storage.get_task(task_id)
    if record is None:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")

    return {
        "task_id": record.task_id,
        "status": record.status,
        "user_task": record.user_task,
        "cost_usd": record.cost_usd,
        "started_at": record.started_at.isoformat() if record.started_at else None,
        "finished_at": record.finished_at.isoformat() if record.finished_at else None,
    }


@app.websocket("/ws/{task_id}")
async def task_websocket(websocket: WebSocket, task_id: str) -> None:
    """Stream progress updates for a running task over WebSocket.

    The client receives JSON messages with fields:
      - type: "progress" | "action" | "complete" | "error"
      - data: varies by type
    """
    await websocket.accept()

    loop = _running_tasks.get(task_id)
    if loop is None:
        await websocket.send_json({"type": "error", "data": f"Task {task_id} not found"})
        await websocket.close()
        return

    try:
        async for update in loop.stream_progress():
            await websocket.send_json(update)
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected for task %s", task_id)
    except Exception:
        logger.exception("WebSocket error for task %s", task_id)
        await websocket.send_json({"type": "error", "data": "Internal error"})
    finally:
        await websocket.close()


# ---------------------------------------------------------------------------
# Health-check
# ---------------------------------------------------------------------------


@app.get("/health")
async def health() -> dict[str, str]:
    """Simple health-check endpoint."""
    return {"status": "ok", "version": "0.1.0"}


# ---------------------------------------------------------------------------
# CLI entry-point
# ---------------------------------------------------------------------------


def main() -> None:
    """Run the orchestrator server via uvicorn."""
    import uvicorn

    uvicorn.run(
        "orchestrator.main:app",
        host="127.0.0.1",
        port=8732,
        reload=True,
        log_level="info",
    )


if __name__ == "__main__":
    main()