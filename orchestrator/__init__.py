"""
Open Cowork — AI Desktop Agent for macOS.

This package provides the agent orchestrator backend for the Open Cowork
project.  It exposes a FastAPI application with REST and WebSocket endpoints
that drive an AI-powered desktop-control loop over the Accessibility API
and CGEvent layer on macOS.
"""

__version__ = "0.1.0"
__all__ = ["main", "agent_loop", "safety", "cost_tracker", "storage", "providers"]