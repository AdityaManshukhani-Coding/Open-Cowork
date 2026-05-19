"""Simple cost tracking utility.

Keeps a running total of token usage and estimated cost. In a real system this
would be persisted and possibly exposed via an endpoint.
"""

from dataclasses import dataclass, field

@dataclass
class CostTracker:
    total_tokens: int = 0
    total_cost: float = 0.0
    history: list[dict] = field(default_factory=list)

    def add_usage(self, tokens: int, cost: float):
        self.total_tokens += tokens
        self.total_cost += cost
        self.history.append({"tokens": tokens, "cost": cost})

    def summary(self) -> dict:
        return {"total_tokens": self.total_tokens, "total_cost": self.total_cost}
