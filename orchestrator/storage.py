"""
Storage layer — persists task history, cost logs, and settings to SQLite.

All data lives locally on the user's machine.  Nothing is uploaded to any
server except what the user explicitly sends to AI model APIs.
"""

from __future__ import annotations

import json
import logging
import sqlite3
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# Default database path inside the user's application support directory.
_DEFAULT_DB_DIR = Path.home() / "Library" / "Application Support" / "com.opencowork.agent"


@dataclass
class TaskRecord:
    """A persisted task record."""

    task_id: str
    user_task: str
    status: str = "pending"
    cost_usd: float = 0.0
    started_at: datetime | None = None
    finished_at: datetime | None = None
    metadata_json: str = "{}"


@dataclass
class SettingsRecord:
    """Persisted user settings."""

    key: str
    value: str


class Storage:
    """SQLite-backed persistence for the agent orchestrator."""

    def __init__(self, db_path: str | Path | None = None) -> None:
        self.db_path = Path(db_path) if db_path else _DEFAULT_DB_DIR / "agent.db"
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn: sqlite3.Connection | None = None

    # ------------------------------------------------------------------
    # Connection management
    # ------------------------------------------------------------------

    def connect(self) -> sqlite3.Connection:
        """Open (or reuse) the database connection."""
        if self._conn is None:
            self._conn = sqlite3.connect(str(self.db_path))
            self._conn.row_factory = sqlite3.Row
            self._conn.execute("PRAGMA journal_mode=WAL")
            self._conn.execute("PRAGMA foreign_keys=ON")
            logger.debug("Storage: connected to %s", self.db_path)
        return self._conn

    def close(self) -> None:
        """Close the database connection."""
        if self._conn is not None:
            self._conn.close()
            self._conn = None
            logger.debug("Storage: connection closed")

    # ------------------------------------------------------------------
    # Schema initialisation
    # ------------------------------------------------------------------

    def initialise_schema(self) -> None:
        """Create tables if they do not yet exist."""
        conn = self.connect()
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS tasks (
                task_id      TEXT PRIMARY KEY,
                user_task    TEXT NOT NULL,
                status       TEXT NOT NULL DEFAULT 'pending',
                cost_usd     REAL NOT NULL DEFAULT 0.0,
                started_at   TEXT,
                finished_at  TEXT,
                metadata_json TEXT NOT NULL DEFAULT '{}'
            );

            CREATE TABLE IF NOT EXISTS settings (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS cost_logs (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id      TEXT REFERENCES tasks(task_id),
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                provider     TEXT NOT NULL DEFAULT 'unknown',
                cost_usd     REAL NOT NULL DEFAULT 0.0,
                created_at   TEXT NOT NULL DEFAULT (datetime('now'))
            );
        """)
        conn.commit()
        logger.debug("Storage: schema initialised")

    # ------------------------------------------------------------------
    # Task CRUD
    # ------------------------------------------------------------------

    async def save_task(self, record: TaskRecord) -> TaskRecord:
        """Insert or update a task record."""
        conn = self.connect()
        conn.execute(
            """
            INSERT INTO tasks (task_id, user_task, status, cost_usd, started_at, finished_at, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET
                status      = excluded.status,
                cost_usd    = excluded.cost_usd,
                finished_at = excluded.finished_at,
                metadata_json = excluded.metadata_json
            """,
            (
                record.task_id,
                record.user_task,
                record.status,
                record.cost_usd,
                record.started_at.isoformat() if record.started_at else None,
                record.finished_at.isoformat() if record.finished_at else None,
                record.metadata_json,
            ),
        )
        conn.commit()
        logger.debug("Storage: saved task %s", record.task_id)
        return record

    async def get_task(self, task_id: str) -> TaskRecord | None:
        """Retrieve a single task by its ID."""
        conn = self.connect()
        row = conn.execute(
            "SELECT * FROM tasks WHERE task_id = ?", (task_id,)
        ).fetchone()
        if row is None:
            return None
        return TaskRecord(
            task_id=row["task_id"],
            user_task=row["user_task"],
            status=row["status"],
            cost_usd=row["cost_usd"],
            started_at=datetime.fromisoformat(row["started_at"]) if row["started_at"] else None,
            finished_at=datetime.fromisoformat(row["finished_at"]) if row["finished_at"] else None,
            metadata_json=row["metadata_json"],
        )

    async def list_tasks(self, limit: int = 20) -> list[TaskRecord]:
        """Return the most recent tasks."""
        conn = self.connect()
        rows = conn.execute(
            "SELECT * FROM tasks ORDER BY started_at DESC LIMIT ?", (limit,)
        ).fetchall()
        return [
            TaskRecord(
                task_id=row["task_id"],
                user_task=row["user_task"],
                status=row["status"],
                cost_usd=row["cost_usd"],
                started_at=datetime.fromisoformat(row["started_at"]) if row["started_at"] else None,
                finished_at=datetime.fromisoformat(row["finished_at"]) if row["finished_at"] else None,
                metadata_json=row["metadata_json"],
            )
            for row in rows
        ]

    # ------------------------------------------------------------------
    # Settings
    # ------------------------------------------------------------------

    async def get_setting(self, key: str, default: str | None = None) -> str | None:
        """Retrieve a single setting value."""
        conn = self.connect()
        row = conn.execute(
            "SELECT value FROM settings WHERE key = ?", (key,)
        ).fetchone()
        return row["value"] if row else default

    async def set_setting(self, key: str, value: str) -> None:
        """Upsert a setting."""
        conn = self.connect()
        conn.execute(
            "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )
        conn.commit()

    # ------------------------------------------------------------------
    # Cost logs
    # ------------------------------------------------------------------

    async def log_cost(
        self,
        task_id: str,
        input_tokens: int,
        output_tokens: int,
        provider: str,
        cost_usd: float,
    ) -> int:
        """Append a cost log entry and return its ID."""
        conn = self.connect()
        cursor = conn.execute(
            """
            INSERT INTO cost_logs (task_id, input_tokens, output_tokens, provider, cost_usd)
            VALUES (?, ?, ?, ?, ?)
            """,
            (task_id, input_tokens, output_tokens, provider, cost_usd),
        )
        conn.commit()
        log_id = cursor.lastrowid
        assert log_id is not None
        return log_id

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def as_dict(self, record: TaskRecord) -> dict[str, Any]:
        """Serialize a TaskRecord to a plain dict for JSON responses."""
        return {
            "task_id": record.task_id,
            "user_task": record.user_task,
            "status": record.status,
            "cost_usd": record.cost_usd,
            "started_at": record.started_at.isoformat() if record.started_at else None,
            "finished_at": record.finished_at.isoformat() if record.finished_at else None,
            "metadata": json.loads(record.metadata_json),
        }