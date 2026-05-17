"""Transparent cost tracking for Open Cowork tasks.

Records per-task and aggregate token usage and estimated spend so
users always know what a task cost them.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from typing import Any

logger = logging.getLogger(__name__)


class CostTracker:
    """In-memory cost ledger (v0.1).  Will be backed by SQLite in v0.2."""

    def __init__(self) -> None:
        """Initialise empty cost tables."""
        self._costs: dict[str, float] = defaultdict(float)
        self._usage: dict[str, list[dict[str, Any]]] = defaultdict(list)

    def add_cost(self, task_id: str, *, usd: float, tokens: int = 0) -> None:
        """Record an additional cost against *task_id*.

        Args:
            task_id: UUID of the running task.
            usd: Estimated spend in US dollars.
            tokens: Number of tokens consumed (optional).
        """
        self._costs[task_id] += usd
        self._usage[task_id].append({"usd": usd, "tokens": tokens})
        logger.debug("Cost recorded for %s: $%.6f", task_id, usd)

    def get_cost(self, task_id: str) -> float:
        """Return the total estimated cost for *task_id*.

        Args:
            task_id: UUID of the task.

        Returns:
            Cumulative USD spend (0.0 if unknown).
        """
        return self._costs.get(task_id, 0.0)

    def get_usage(self, task_id: str) -> list[dict[str, Any]]:
        """Return the raw usage log for *task_id*.

        Args:
            task_id: UUID of the task.

        Returns:
            List of usage entries.
        """
        return self._usage.get(task_id, [])
