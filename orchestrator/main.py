"""FastAPI entry point for the Open Cowork orchestrator.

Provides HTTP endpoints for task submission, status retrieval, and a WebSocket
for real‑time updates. All routes are deliberately minimal for the v0.1
foundation.
"""

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import asyncio

from . import storage, agent_loop, safety

app = FastAPI(title="Open Cowork Orchestrator")

# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class TaskRequest(BaseModel):
    task_id: str
    prompt: str

# ---------------------------------------------------------------------------
# HTTP endpoints
# ---------------------------------------------------------------------------

@app.post("/task")
async def submit_task(request: TaskRequest):
    """Submit a new task.

    The request is validated, passes through a safety check, and is stored for
    processing by the background agent loop.
    """
    if not safety.check_allowed(request):
        raise HTTPException(status_code=403, detail="Task blocked by safety policy")
    await storage.save_task(request.task_id, request.prompt)
    return JSONResponse(content={"status": "queued", "task_id": request.task_id})

@app.get("/status")
async def get_status():
    """Return pending and completed tasks."""
    pending = await storage.list_pending()
    completed = await storage.list_completed()
    return {"pending": pending, "completed": completed}

# ---------------------------------------------------------------------------
# WebSocket endpoint (placeholder implementation)
# ---------------------------------------------------------------------------

class ConnectionManager:
    def __init__(self):
        self.active: list[WebSocket] = []

    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.active.append(ws)

    def disconnect(self, ws: WebSocket):
        self.active.remove(ws)

    async def broadcast(self, message: str):
        for ws in self.active:
            await ws.send_text(message)

manager = ConnectionManager()

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await manager.connect(ws)
    try:
        while True:
            await asyncio.sleep(5)
            await manager.broadcast("heartbeat")
    except WebSocketDisconnect:
        manager.disconnect(ws)

# ---------------------------------------------------------------------------
# Startup – launch background agent loop
# ---------------------------------------------------------------------------

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(agent_loop.run())

