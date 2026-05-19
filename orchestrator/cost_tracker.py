"""
Cost tracker — monitors token usage and estimates per-task spend.

Tracks input/output token counts for each provider call, computes an
estimated cost based on the provider's published pricing, and aggregates
totals per session.  Designed to give users full transparency into what
each task costs.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

# Known per-1K-token pricing (USD).  Source: provider pricing pages as of 2025-05.
# These are used as defaults; users may override via config.
PROVIDER_PRICING: dict[str, dict[str, float]] = {
    "anthropic": {
        "input_per_1k": 0.003,   # Claude Sonnet 4
        "output_per_1k": 0.015,
    },
    "openai": {
        "input_per_1k": 0.0025,  # GPT-4o
        "output_per_1k": 0.010,
    },
    "ollama": {
        "input_per_1k": 0.0,     # Local — free
        "output_per_1k": 0.0,
    },
}


@dataclass
class UsageRecord:
    """Token usage for a single provider call."""

    input_tokens: int = 0
    output_tokens: int = 0
    provider: str = "unknown"
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def cost_usd(self) -> float:
        """Estimated cost of this call in USD."""
        pricing = PROVIDER_PRICING.get(self.provider, PROVIDER_PRICING["openai"])
        input_cost = (self.input_tokens / 1000.0) * pricing["input_per_1k"]
        output_cost = (self.output_tokens / 1000.0) * pricing["output_per_1k"]
        return round(input_cost + output_cost, 6)


@dataclass
class SessionCost:
    """Aggregated cost data for an entire task session."""

    total_input_tokens: int = 0
    total_output_tokens: int = 0
    total_cost_usd: float = 0.0
    call_count: int = 0
    records: list[UsageRecord] = field(default_factory=list)


class CostTracker:
    """Per-session token and cost accumulator."""

    def __init__(self, budget_limit_usd: float | None = None) -> None:
        self.budget_limit_usd = budget_limit_usd
        self._session: SessionCost | None = None

    # ------------------------------------------------------------------
    # Session lifecycle
    # ------------------------------------------------------------------

    def start_session(self) -> None:
        """Begin a new cost-tracking session."""
        self._session = SessionCost()
        logger.debug("CostTracker: session started (budget=%s)", self.budget_limit_usd)

    def end_session(self) -> float:
        """Finalise the session and return the total cost in USD."""
        if self._session is None:
            return 0.0
        total = round(self._session.total_cost_usd, 4)
        logger.info(
            "CostTracker: session ended — %d calls, %.4f USD total",
            self._session.call_count,
            total,
        )
        self._session = None
        return total

    # ------------------------------------------------------------------
    # Recording
    # ------------------------------------------------------------------

    def record_usage(
        self,
        input_tokens: int,
        output_tokens: int,
        provider: str = "unknown",
    ) -> UsageRecord:
        """Record a single provider call's token usage."""
        record = UsageRecord(
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            provider=provider,
        )
        if self._session is not None:
            self._session.total_input_tokens += input_tokens
            self._session.total_output_tokens += output_tokens
            self._session.total_cost_usd += record.cost_usd
            self._session.call_count += 1
            self._session.records.append(record)

            if self.budget_limit_usd is not None:
                if self._session.total_cost_usd >= self.budget_limit_usd:
                    logger.warning(
                        "CostTracker: budget limit hit (%.4f >= %.4f)",
                        self._session.total_cost_usd,
                        self.budget_limit_usd,
                    )
                    # TODO: Signal the agent loop to pause / stop.
        return record

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------

    @property
    def current_cost(self) -> SessionCost | None:
        """Return the current session's cost snapshot, or *None* if no
        session is active."""
        return self._session

    @property
    def is_over_budget(self) -> bool:
        """Return *True* if the session has exceeded the configured budget
        limit."""
        if self._session is None or self.budget_limit_usd is None:
            return False
        return self._session.total_cost_usd >= self.budget_limit_usd