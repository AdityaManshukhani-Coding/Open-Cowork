"""
Core agent loop — plans, executes, and monitors multi-step desktop tasks.

This is the central loop that:
1. Receives a natural-language task from the user.
2. Calls the configured AI provider to reason about the next action.
3. Dispatches the action to the macOS control layer.
4. Captures the resulting screen state and loops until completion.
5. Reports progress and cost information to the caller.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from enum import Enum
from typing import AsyncIterator

from orchestrator.cost_tracker import CostTracker
from orchestrator.providers import ChatMessage, ProviderAdapter
from orchestrator.safety import SafetyGate, SafetyMode
from orchestrator.storage import TaskRecord, Storage

logger = logging.getLogger(__name__)


class TaskStatus(str, Enum):
    """Possible states for a task throughout its lifecycle."""

    PENDING = "pending"
    RUNNING = "running"
    WAITING_FOR_APPROVAL = "waiting_for_approval"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class AgentLoop:
    """Drives the perceive-reason-act cycle for a single task."""

    def __init__(
        self,
        task_id: str,
        user_task: str,
        provider: ProviderAdapter,
        safety: SafetyGate,
        cost_tracker: CostTracker,
        storage: Storage,
        *,
        max_steps: int = 50,
    ) -> None:
        self.task_id = task_id
        self.user_task = user_task
        self._provider = provider
        self._safety = safety
        self._cost_tracker = cost_tracker
        self._storage = storage
        self.max_steps = max_steps
        self.status = TaskStatus.PENDING
        self.conversation_history: list[ChatMessage] = []
        self._cancelled = False

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def run(self) -> TaskRecord:
        """Execute the agent loop from start to finish (or failure)."""
        logger.info("AgentLoop[%s] starting task: %s", self.task_id, self.user_task)

        self.status = TaskStatus.RUNNING
        self._cost_tracker.start_session()

        try:
            for step in range(1, self.max_steps + 1):
                if self._cancelled:
                    self.status = TaskStatus.CANCELLED
                    break

                # --- Perceive ---
                screenshot_base64, accessibility_tree = await self._capture_state()

                # --- Reason ---
                action_plan = await self._reason_next_action(
                    step, screenshot_base64, accessibility_tree
                )

                if action_plan is None:
                    self.status = TaskStatus.COMPLETED
                    break

                # --- Safety gate ---
                if self._safety.mode in (SafetyMode.APPROVE_BEFORE_ACTION, SafetyMode.STEP_THROUGH):
                    self.status = TaskStatus.WAITING_FOR_APPROVAL
                    approved = await self._safety.approve_action(action_plan)
                    if not approved:
                        self.status = TaskStatus.CANCELLED
                        break
                    self.status = TaskStatus.RUNNING

                # --- Act ---
                await self._execute_action(action_plan)

                # --- Record ---
                await self._record_step(step, action_plan)

                # --- Yield control so the event loop stays responsive ---
                await asyncio.sleep(0)

            else:
                logger.warning("AgentLoop[%s] hit max steps (%d)", self.task_id, self.max_steps)

        except Exception:
            self.status = TaskStatus.FAILED
            logger.exception("AgentLoop[%s] failed unexpectedly", self.task_id)
        finally:
            session_cost = self._cost_tracker.end_session()
            record = await self._storage.save_task(
                TaskRecord(
                    task_id=self.task_id,
                    user_task=self.user_task,
                    status=self.status.value,
                    cost_usd=session_cost,
                    started_at=datetime.now(timezone.utc),
                )
            )
            logger.info(
                "AgentLoop[%s] finished status=%s cost=%.4f",
                self.task_id,
                self.status.value,
                session_cost,
            )
            return record

    async def cancel(self) -> None:
        """Request cancellation of a running loop."""
        self._cancelled = True
        logger.info("AgentLoop[%s] cancellation requested", self.task_id)

    async def stream_progress(self) -> AsyncIterator[dict]:
        """Yield progress updates for live streaming to the UI."""
        ...
        yield {}  # pragma: no cover

    # ------------------------------------------------------------------
    # Internal helpers — to be fleshed out in later iterations
    # ------------------------------------------------------------------

    async def _capture_state(self) -> tuple[str | None, str | None]:
        """Capture current screen state.

        Returns (base64_screenshot, accessibility_tree_string).
        Both can be None if the capture medium is unavailable.
        """
        # TODO: Wire in ScreenCaptureKit and Accessibility API calls.
        return None, None

    async def _reason_next_action(
        self,
        step: int,
        screenshot: str | None,
        accessibility_tree: str | None,
    ) -> str | None:
        """Call the AI provider to decide the next action.

        Returns a natural-language action description, or *None* when the
        agent considers the task complete.
        """
        messages = list(self.conversation_history)
        system_prompt = (
            f"You are an AI desktop assistant controlling macOS. "
            f"User task: {self.user_task}\n"
            f"Step {step}. Determine the next action. "
            f"If the task is done, respond with 'TASK_COMPLETE'."
        )
        if accessibility_tree:
            system_prompt += f"\n\nAccessibility tree:\n{accessibility_tree[:2000]}"

        reply = await self._provider.chat(
            messages=messages, system=system_prompt, temperature=0.3
        )

        if "TASK_COMPLETE" in reply.strip().upper():
            return None

        self.conversation_history.append(ChatMessage(role="user", content=system_prompt))
        self.conversation_history.append(ChatMessage(role="assistant", content=reply))
        return reply

    async def _execute_action(self, action_plan: str) -> None:
        """Dispatch an action to the macOS control layer."""
        # TODO: Parse action_plan and call AXUIElement / CGEvent helpers.
        logger.debug("AgentLoop[%s] executing: %s", self.task_id, action_plan[:120])

    async def _record_step(self, step: int, action: str) -> None:
        """Persist a single step to storage for audit / replay."""
        # TODO: Store step details in the database.
        del step, action  # unused until storage schema is extended