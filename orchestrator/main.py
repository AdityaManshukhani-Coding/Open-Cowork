"""FastAPI entry point for the Open Cowork orchestrator.

Defines HTTP endpoints for task submission and status queries, as well as a
WebSocket endpoint for real‑time streaming of agent actions.
"""

from fastapi import FastAPI, WebSocket, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uuid

from .agent_loop import AgentLoop
from .storage import TaskStorage

app = FastAPI(title="Open Cowork Orchestrator")

# Simple in‑memory storage (could be swapped for SQLite later)
storage = TaskStorage()
agent_loop = AgentLoop(storage)


class TaskRequest(BaseModel):
    """Payload for creating a new task."""

    prompt: str
    # Additional fields (e.g., model, safety_mode) could be added here.


@app.post("/task")
async def create_task(request: TaskRequest):
    """Create a new task and start the agent loop.

    Returns a JSON object containing the generated ``task_id``.
    """
    task_id = str(uuid.uuid4())
    await storage.save_task(task_id, {"prompt": request.prompt, "status": "queued"})
    # Fire‑and‑forget the agent loop for this task.
    agent_loop.start_task(task_id, request.prompt)
    return JSONResponse(content={"task_id": task_id})


@app.get("/status/{task_id}")
async def get_status(task_id: str):
    """Return the current status of a task.

    Raises ``404`` if the task does not exist.
    """
    task = await storage.get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return JSONResponse(content={"task_id": task_id, "status": task.get("status")})


@app.websocket("/ws/{task_id}")
async def websocket_endpoint(websocket: WebSocket, task_id: str):
    """WebSocket stream for a specific task.

    The client receives JSON messages with ``event`` and ``data`` fields.
    """
    await websocket.accept()
    if not await storage.task_exists(task_id):
        await websocket.send_json({"event": "error", "data": "Task not found"})
        await websocket.close()
        return
    # Register the websocket with the agent loop so it receives updates.
    await agent_loop.register_ws(task_id, websocket)
    try:
        while True:
            # Keep the connection alive; the agent loop pushes messages.
            await websocket.receive_text()
    except Exception:
        # Client disconnected – clean up.
        await agent_loop.unregister_ws(task_id, websocket)
        await websocket.close()
