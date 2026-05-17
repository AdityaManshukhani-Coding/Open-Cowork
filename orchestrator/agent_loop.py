"""Core agent execution loop for Open Cowork.

The ``AgentLoop`` drives a task from queue through completion by
interacting with the chosen AI provider, the macOS control layer, and
the safety / cost subsystems.
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from orchestrator.cost_tracker import CostTracker
    from orchestrator.safety import SafetyGuard

logger = logging.getLogger(__name__)


@dataclass
class TaskState:
    """Mutable container for the runtime state of a single task."""

    task_id: str
    instruction: str
    model: str | None = None
    provider: str | None = None
    status: str = "queued"  # queued | running | paused | completed | failed
    actions: list[dict] = field(default_factory=list)


class AgentLoop:
    """Orchestrates one turn of the agent reasoning → action cycle."""

    @staticmethod
    async def run(
        *,
        task_id: str,
        state: TaskState,
        tracker: "CostTracker",
        guard: "SafetyGuard",
    ) -> None:
        """Execute *state* until completion, failure, or user stop.

        Args:
            task_id: UUID of the task.
            state: Mutable task state object.
            tracker: Shared cost tracker instance.
            guard: Shared safety guard instance.
        """
        state.status = "running"
        logger.info("[%s] Agent loop started for: %s", task_id, state.instruction)

        try:
            # TODO(v0.2): integrate provider selection, screenshot capture,
            #             AXUIElement queries, and CGEvent dispatch.
            await asyncio.sleep(0.1)  # placeholder work

            # Simulate a single action for the skeleton.
            action = {"type": "noop", "reason": "skeleton implementation"}
            state.actions.append(action)

            # Safety check (placeholder)
            if not guard.is_allowed(action):
                state.status = "failed"
                logger.warning("[%s] Action blocked by safety guard", task_id)
                return

            # Cost tracking (placeholder)
            tracker.add_cost(task_id, usd=0.0)

            state.status = "completed"
            logger.info("[%s] Agent loop completed", task_id)
        except Exception as exc:  # pragma: no cover
            state.status = "failed"
            logger.exception("[%s] Agent loop error: %s", task_id, exc)
