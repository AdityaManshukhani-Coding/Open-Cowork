"""In‑memory async storage for tasks.

A lightweight stand‑in for a real database. Stores pending tasks, completed
tasks, and results. All functions are async to match typical FastAPI usage.
"""

from typing import Dict, List

# In‑memory stores
_tasks: Dict[str, Dict] = {}
_results: Dict[str, str] = {}

async def save_task(task_id: str, prompt: str) -> None:
    _tasks[task_id] = {"task_id": task_id, "prompt": prompt, "status": "pending"}

async def fetch_pending() -> List[Dict]:
    return [t for t in _tasks.values() if t["status"] == "pending"]

async def update_status(task_id: str, status: str) -> None:
    if task_id in _tasks:
        _tasks[task_id]["status"] = status

async def save_result(task_id: str, result: str) -> None:
    results[task_id] = result

async def list_pending() -> List[Dict]:
    return await fetch_pending()

async def list_completed() -> List[Dict]:
    return [t for t in _tasks.values() if t["status"] == "completed"]

async def save_task_result(task_id: str, result: str) -> None:
    await save_result(task_id, result)
