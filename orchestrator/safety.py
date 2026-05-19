"""Safety utilities for the orchestrator.

Placeholder implementations that always allow tasks. Real checks will enforce
cost limits, approval modes, and per‑app allowlists.
"""

from .cost_tracker import CostTracker

_cost_tracker = CostTracker()

def check_allowed(task) -> bool:
    return True

def check_allowed_prompt(prompt: str) -> bool:
    return True
