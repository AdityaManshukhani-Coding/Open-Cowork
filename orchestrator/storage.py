"""Local persistence layer for Open Cowork.

Intended to back task history, cost logs, and settings with SQLite.
All methods are async-ready (using aiosqlite) so they can be called
from the FastAPI event loop without blocking.
"""

from __future__ import annotations

import logging
import sqlite3
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_DB_PATH = Path(__file__).with_suffix(".db").resolve()


def _get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(_DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


class Storage:
    """Thin wrapper around a local SQLite database."""

    def __init__(self) -> None:
        """Ensure the database file and schema exist."""
        self._init_db()

    def _init_db(self) -> None:
        with _get_conn() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    task_id   TEXT PRIMARY KEY,
                    created   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    status    TEXT,
                    instruction TEXT,
                    model     TEXT,
                    provider  TEXT
                );
                CREATE TABLE IF NOT EXISTS costs (
                    id        INTEGER PRIMARY KEY AUTOINCREMENT,
                    task_id   TEXT,
                    usd       REAL,
                    tokens    INTEGER,
                    recorded  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """
            )
            conn.commit()
        logger.info("Storage initialised at %s", _DB_PATH)

    def save_task(self, task_id: str, payload: dict[str, Any]) -> None:
        """Persist a task record.

        Args:
            task_id: UUID of the task.
            payload: Dictionary with keys ``instruction``, ``model``,
                ``provider``, ``status``.
        """
        with _get_conn() as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO tasks
                (task_id, instruction, model, provider, status)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    task_id,
                    payload.get("instruction"),
                    payload.get("model"),
                    payload.get("provider"),
                    payload.get("status", "queued"),
                ),
            )
            conn.commit()
        logger.debug("Task %s saved to storage", task_id)
