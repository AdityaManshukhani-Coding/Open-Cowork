"""
Safety gating layer — controls how the agent interacts with the user's system.

Provides four control modes:
- FULL_AUTO: The agent acts without user intervention.
- APPROVE_BEFORE_ACTION: The agent pauses before each action and waits for
  approval.
- STEP_THROUGH: The agent requires manual confirmation for every single step.
- EMERGENCY_STOP: The agent halts immediately and refuses further actions.

Also enforces per-app allowlists, prompt-injection heuristics, and an
emergency-stop mechanism.
"""

from __future__ import annotations

import logging
from enum import Enum

logger = logging.getLogger(__name__)


class SafetyMode(str, Enum):
    """Available safety control modes."""

    FULL_AUTO = "full_auto"
    APPROVE_BEFORE_ACTION = "approve_before_action"
    STEP_THROUGH = "step_through"
    EMERGENCY_STOP = "emergency_stop"


class SafetyGate:
    """Evaluates whether an action is safe to execute."""

    def __init__(
        self,
        mode: SafetyMode = SafetyMode.APPROVE_BEFORE_ACTION,
        app_allowlist: list[str] | None = None,
    ) -> None:
        self.mode = mode
        self.app_allowlist: set[str] = set(app_allowlist or [])
        self._emergency_stop = mode == SafetyMode.EMERGENCY_STOP

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def approve_action(self, action_description: str) -> bool:
        """Check whether an action is allowed.

        Returns *True* if the action passes all safety checks.
        In EMERGENCY_STOP mode this always returns *False*.
        """
        if self._emergency_stop:
            logger.warning("SafetyGate: emergency stop — action denied")
            return False

        if not self._app_allowlist_check(action_description):
            logger.warning("SafetyGate: app not in allowlist — action denied")
            return False

        if self._detect_prompt_injection(action_description):
            logger.warning("SafetyGate: possible prompt injection detected — action denied")
            return False

        return True

    def engage_emergency_stop(self) -> None:
        """Immediately halt all agent actions."""
        self._emergency_stop = True
        self.mode = SafetyMode.EMERGENCY_STOP
        logger.info("SafetyGate: emergency stop engaged")

    def disengage_emergency_stop(self) -> None:
        """Re-enable the agent after an emergency stop."""
        self._emergency_stop = False
        self.mode = SafetyMode.APPROVE_BEFORE_ACTION
        logger.info("SafetyGate: emergency stop disengaged")

    def update_allowlist(self, apps: list[str]) -> None:
        """Replace the per-app allowlist."""
        self.app_allowlist = set(apps)

    # ------------------------------------------------------------------
    # Internal checks
    # ------------------------------------------------------------------

    def _app_allowlist_check(self, action: str) -> bool:
        """Return *False* if the action targets an app not in the allowlist
        and the allowlist is non-empty (empty = no restriction)."""
        if not self.app_allowlist:
            return True
        action_lower = action.lower()
        for app in self.app_allowlist:
            if app.lower() in action_lower:
                return True
        return False

    @staticmethod
    def _detect_prompt_injection(text: str) -> bool:
        """Basic heuristic for prompt injection attempts.

        Looks for imperative instructions that try to override the agent's
        behaviour from screen content.
        """
        injection_patterns = [
            "ignore your previous instructions",
            "ignore all previous instructions",
            "you are now",
            "you must act as",
            "system prompt",
            "forget everything",
            "new instructions",
        ]
        text_lower = text.lower()
        return any(pattern in text_lower for pattern in injection_patterns)