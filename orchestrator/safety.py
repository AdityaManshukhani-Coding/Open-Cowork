"""Safety utilities for the orchestrator.

Placeholder module that will later contain cost‑limit checks, approval
gateways, and emergency‑stop handling. For now it provides a simple
function that can be expanded without breaking imports.
"""

def check_cost_limit(current_cost: float, limit: float) -> bool:
    """Return ``True`` if the current cost is within the allowed *limit*.

    The real implementation will integrate with :pymod:`cost_tracker`.
    """
    return current_cost <= limit
