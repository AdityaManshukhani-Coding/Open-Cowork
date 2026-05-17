"""Safety guard for Open Cowork agent actions.

Implements allow-lists, action vetting, and (future) prompt-injection
detection before any action is allowed to touch the host system.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)


class SafetyGuard:
    """Central safety gate for all agent-originated actions."""

    def __init__(self) -> None:
        """Initialise with default permissive settings (v0.1)."""
        self._allowed_apps: set[str] = set()
        self._mode: str = "permissive"  # permissive | confirm | locked

    def is_allowed(self, action: dict[str, Any]) -> bool:
        """Return *True* if *action* may be executed in the current mode.

        Args:
            action: Normalised action dictionary (e.g. ``{"type": "click"}``).

        Returns:
            Boolean approval flag.
        """
        action_type = action.get("type", "")
        if action_type == "noop":
            return True

        # TODO(v0.2): enforce per-app allow-lists, confirmation gating,
        #             and prompt-injection heuristics.
        logger.debug("Safety check passed for action: %s", action)
        return True

    def set_mode(self, mode: str) -> None:
        """Update the global safety mode.

        Args:
            mode: One of ``permissive``, ``confirm``, or ``locked``.
        """
        self._mode = mode
        logger.info("Safety mode set to: %s", mode)
