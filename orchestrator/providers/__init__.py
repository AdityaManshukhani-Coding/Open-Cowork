"""AI provider integrations for Open Cowork.

Each submodule implements a thin adapter around a single provider's
HTTP API, exposing a uniform ``generate()`` coroutine that the agent
loop can call without knowing which backend is in use.
"""
