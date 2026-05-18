"""
╔══════════════════════════════════════════════════════════════════════════════╗
║               AUTONOMOUS CODING TEAM — LangGraph Supervisor                ║
║                    Production-grade overnight orchestration                 ║
║                     Nvidia NIM API · SQLite Checkpoints                    ║
╚══════════════════════════════════════════════════════════════════════════════╝

Architecture:
  Supervisor (Manager) → reviews codebase, maps milestones, delegates tasks
    ├── Worker 1: Backend Coder  (FileRead + FileWrite + Shell tools)
    ├── Worker 2: UI Artist       (FileRead + FileWrite tools)
    └── Worker 3: Tester / QA     (Shell tool + git auto-commit gating)

Safety:
  • SQLite checkpointing → survives API failures and timeouts
  • Recursion limit of 40 → no infinite loops overnight
  • Auto git-commit on every passing milestone → rollback safety net

Requirements:
  pip install langgraph langchain-openai langchain-core

Usage:
  python orchestrate_langgraph.py
  python orchestrate_langgraph.py "Build a Flask REST API for a todo app"
"""

from __future__ import annotations

import functools
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Annotated, List, Optional, TypedDict
from langgraph.graph.message import add_messages

# ─────────────────────────────────────────────────────────────────────────────
# API CONFIGURATION — Replace with your Nvidia NIM keys
# ─────────────────────────────────────────────────────────────────────────────

NVIDIA_API_BASE = "https://integrate.api.nvidia.com/v1"

MANAGER_API_KEY = os.environ.get(
    "NVIDIA_MANAGER_KEY",
    "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",
)
BACKEND_CODER_KEY = os.environ.get(
    "NVIDIA_BACKEND_KEY",
    "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",
)
UI_ARTIST_KEY = os.environ.get(
    "NVIDIA_UI_KEY",
    "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",
)
TESTER_KEY = os.environ.get(
    "NVIDIA_TESTER_KEY",
    "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",
)

MANAGER_MODEL = "moonshotai/kimi-k2.6"
WORKER_MODEL = "moonshotai/kimi-k2.6"

# ─────────────────────────────────────────────────────────────────────────────
# RESILIENCE SETTINGS
# ─────────────────────────────────────────────────────────────────────────────

RECURSION_LIMIT = 400
os.environ.setdefault("LITELLM_NUM_RETRIES", "1000")
os.environ.setdefault("LITELLM_MAX_RETRY_DELAY", "60")
os.environ.setdefault("LITELLM_REQUEST_TIMEOUT", "60")

# ─────────────────────────────────────────────────────────────────────────────
# WORKSPACE — the main Open Cowork project directory
# ─────────────────────────────────────────────────────────────────────────────

WORKSPACE_PATH = Path(__file__).resolve().parent
CHECKPOINT_DB = WORKSPACE_PATH / "agent_checkpoints.db"

# ─────────────────────────────────────────────────────────────────────────────
# IMPORTS  (deferred so config block stays clean at the top)
# ─────────────────────────────────────────────────────────────────────────────

from langchain_openai import ChatOpenAI
from langchain_core.messages import AIMessage, BaseMessage, HumanMessage
from langchain_core.tools import tool
from langgraph.prebuilt import create_react_agent
from langgraph.checkpoint.sqlite import SqliteSaver


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              S T A T E                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

class TeamState(TypedDict):
    """Shared state across the supervisor and all workers.

    ``create_supervisor`` manages its own internal state around the ``messages``
    key; the extra fields are injected into the initial state so they appear in
    the conversation context for the supervisor to reason about.
    """

    messages: Annotated[List[BaseMessage], add_messages]
    task_description: str
    project_root: str


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                               T O O L S                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

@tool
def file_read_tool(path: str) -> str:
    """Read the complete contents of a file inside the project workspace and
    return it as a string.  ``path`` must be relative to the project root."""
    full = (WORKSPACE_PATH / path).resolve()
    if not str(full).startswith(str(WORKSPACE_PATH.resolve())):
        return f"ERROR: path {path!r} escapes the workspace."
    try:
        return full.read_text(encoding="utf-8")
    except FileNotFoundError:
        return f"ERROR: file {path!r} not found."
    except Exception as exc:
        return f"ERROR reading {path!r}: {exc}"


@tool
def file_write_tool(path: str, content: str) -> str:
    """Create or overwrite a file inside the project workspace.  ``path`` must
    be relative to the project root.  ``content`` is the full file body."""
    full = (WORKSPACE_PATH / path).resolve()
    if not str(full).startswith(str(WORKSPACE_PATH.resolve())):
        return f"ERROR: path {path!r} escapes the workspace."
    try:
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(content, encoding="utf-8")
        return f"OK: wrote {len(content)} bytes to {path!r}."
    except Exception as exc:
        return f"ERROR writing {path!r}: {exc}"


@tool
def shell_tool(command: str) -> str:
    """Execute a terminal command inside the project workspace and return
    stdout + stderr.  Use for running tests, linters, compilers, package
    managers, or git operations."""
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=120,
            cwd=str(WORKSPACE_PATH),
        )
        out = ""
        if result.stdout.strip():
            out += f"STDOUT:\n{result.stdout}"
        if result.stderr.strip():
            out += f"\nSTDERR:\n{result.stderr}"
        out += f"\nEXIT: {result.returncode}"
        return out
    except subprocess.TimeoutExpired:
        return "ERROR: command timed out after 120 s."
    except Exception as exc:
        return f"ERROR: {exc}"


@tool
def git_snapshot_tool(commit_message: str) -> str:
    """Stage all changes and create a git commit with the given message.
    Only call this when you (the Tester) have confirmed compilation / tests pass.
    Returns the commit hash on success."""
    try:
        subprocess.run(
            ["git", "add", "."],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(WORKSPACE_PATH),
        )
        result = subprocess.run(
            ["git", "commit", "-m", commit_message],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(WORKSPACE_PATH),
        )
        if result.returncode != 0:
            if "nothing to commit" in result.stdout + result.stderr:
                return "NOTHING TO COMMIT"
            return f"COMMIT FAILED:\n{result.stdout}\n{result.stderr}"

        hash_result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=str(WORKSPACE_PATH),
        )
        return f"COMMITTED: {hash_result.stdout.strip()} — {commit_message}"
    except Exception as exc:
        return f"GIT ERROR: {exc}"


@tool
def list_workspace_tool(path: str = ".") -> str:
    """List files and directories at a relative path inside the workspace.
    Useful for exploring the codebase before making changes."""
    full = (WORKSPACE_PATH / path).resolve()
    if not str(full).startswith(str(WORKSPACE_PATH.resolve())):
        return f"ERROR: path {path!r} escapes the workspace."
    try:
        items = sorted(full.iterdir())
        lines = []
        for item in items:
            suffix = "/" if item.is_dir() else ""
            size = ""
            if item.is_file():
                try:
                    size = f"  ({item.stat().st_size} B)"
                except OSError:
                    pass
            lines.append(f"  {item.name}{suffix}{size}")
        return f"Contents of {path!r}:\n" + "\n".join(lines) if lines else f"{path!r} is empty."
    except FileNotFoundError:
        return f"ERROR: path {path!r} not found."
    except Exception as exc:
        return f"ERROR: {exc}"


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                           L L M   F A C T O R Y                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

def _build_llm(api_key: str, model: str, temperature: float) -> ChatOpenAI:
    """Return a ChatOpenAI instance pointed at the Nvidia NIM endpoint."""
    return ChatOpenAI(
        api_key=api_key,
        base_url=NVIDIA_API_BASE,
        model=model,
        temperature=temperature,
        max_tokens=500000,  # effectively unlimited for our use case
        timeout=90,
        max_retries=1000,
    )


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     W O R K E R   A G E N T S                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

backend_coder = create_react_agent(
    model=_build_llm(BACKEND_CODER_KEY, WORKER_MODEL, temperature=0.1),
    tools=[file_read_tool, file_write_tool, shell_tool, list_workspace_tool],
    prompt=(
        "You are the Backend Coder — a senior engineer specialized in core "
        "application logic, data models, APIs, and system architecture.\n\n"
        "RULES:\n"
        "1. Always read relevant files first with file_read_tool before editing.\n"
        "2. Use file_write_tool to create or modify files.\n"
        "3. Use shell_tool to run compilers, linters, or package managers.\n"
        "4. Write clean, production-quality code. No TODOs left behind.\n"
        "5. Follow existing project conventions and patterns.\n"
        "6. After completing your work, report exactly what files you changed."
    ),
    name="Backend_Coder",
)

ui_artist = create_react_agent(
    model=_build_llm(UI_ARTIST_KEY, WORKER_MODEL, temperature=0.3),
    tools=[file_read_tool, file_write_tool, list_workspace_tool],
    prompt=(
        "You are the UI Artist — a frontend specialist focused on visual "
        "presentation, stylesheets, templates, and user-facing layouts.\n\n"
        "RULES:\n"
        "1. Always read existing UI files first to match conventions.\n"
        "2. Use file_write_tool for all changes.\n"
        "3. Prioritize polished, production-grade visuals.\n"
        "4. Add hover states, transitions, and micro-interactions.\n"
        "5. Report every file you modify with a short summary."
    ),
    name="UI_Artist",
)

tester_qa = create_react_agent(
    model=_build_llm(TESTER_KEY, WORKER_MODEL, temperature=0.0),
    tools=[shell_tool, file_read_tool, list_workspace_tool, git_snapshot_tool],
    prompt=(
        "You are the Tester / QA — a meticulous quality engineer.\n\n"
        "RULES:\n"
        "1. Read changed files to understand what was built.\n"
        "2. Use shell_tool to run verification:\n"
        "   - Python: python -m py_compile <file> or flake8 / pytest\n"
        "   - TypeScript/JS: tsc --noEmit / eslint / jest\n"
        "   - Swift: swift build / xcodebuild\n"
        "   - Generic: check syntax, run the test suite.\n"
        "3. If ALL checks pass, YOU MUST call git_snapshot_tool with a "
        "Conventional Commits message (e.g. 'feat: add orchestrator skeleton').\n"
        "4. Only after committing, respond with the exact phrase "
        "\"ALL CHECKS PASSED — COMMITTED\".\n"
        "5. If anything fails, report the exact errors clearly — DO NOT commit."
    ),
    name="Tester_QA",
)


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     S U P E R V I S O R   G R A P H                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

from typing import Literal
from pydantic import BaseModel, Field

# Define structured routing options for the supervisor
class RouterOptions(BaseModel):
    next_step: Literal["Backend_Coder", "UI_Artist", "Tester_QA", "FINISH"] = Field(
        description="The next worker to handle the task, or FINISH if completely done."
    )

def supervisor_node(state: TeamState):
    """Manual supervisor implementation matching LangGraph 0.6.x layout."""
    llm = _build_llm(MANAGER_API_KEY, MANAGER_MODEL, temperature=0.2)
    
    # Bind the structural output so the LLM must choose a destination
    structured_llm = llm.with_structured_output(RouterOptions)
    
    
    system_prompt =(
        "You are the Project Manager / Supervisor of an autonomous coding "
        "team. Your job is to take a high-level project requirement and "
        "orchestrate its implementation through your workers.\n\n"
        "YOUR WORKERS:\n"
        "- Backend_Coder: writes application logic, data models, APIs, core code.\n"
        "- UI_Artist: handles visual presentation, styles, templates, front-end.\n"
        "- Tester_QA: runs compilers, linters, test suites AND creates git commits "
        "when all checks pass.\n\n"
        "WORKFLOW:\n"
        "1. Break the task into clear milestones (share them in your first message).\n"
        "2. For each milestone, delegate to the appropriate worker.\n"
        "3. After EVERY code change, delegate to Tester_QA for verification.\n"
        "4. If Tester_QA reports failures, send the error feedback back to the "
        "coder that made the changes.\n"
        "5. If Tester_QA reports \"ALL CHECKS PASSED — COMMITTED\", move to "
        "the next milestone.\n"
        "6. Continue until all milestones are complete.\n\n"
        "CRITICAL:\n"
        "- Never delegate to two workers simultaneously — sequential only.\n"
        "- Never skip the Tester_QA step after code changes.\n"
        "- When the project is fully complete, respond with \"PROJECT COMPLETE\"."
    )



    messages = [HumanMessage(content=system_prompt)] + state["messages"]
    response = structured_llm.invoke(messages)
    
    # Inject routing choice into the state message history
    return {
        "messages": [AIMessage(content=f"Supervisor designated: {response.next_step}")],
        "next_destination": response.next_step
    }

# Extend TeamState to include the router tracking field
# Extend TeamState to include the router tracking field
class TeamState(TypedDict):
    messages: Annotated[List[BaseMessage], add_messages]
    task_description: str
    project_root: str
    next_destination: str  # Added for state-based routing


# Pull this entirely out of the class definition block (0 indentation)
@functools.lru_cache(maxsize=1)
def _get_compiled_graph():
    """Build and compile the multi-agent state graph using 0.6.x syntax."""
    from langgraph.graph import StateGraph, END
    
    workflow = StateGraph(TeamState)
    
    # Add all agent nodes
    workflow.add_node("supervisor", supervisor_node)
    workflow.add_node("Backend_Coder", backend_coder)
    workflow.add_node("UI_Artist", ui_artist)
    workflow.add_node("Tester_QA", tester_qa)
    
    # Define directional returns back to supervisor
    workflow.add_edge("Backend_Coder", "supervisor")
    workflow.add_edge("UI_Artist", "supervisor")
    workflow.add_edge("Tester_QA", "supervisor")
    
    # Configure dynamic conditional routing from the supervisor node
    workflow.add_conditional_edges(
        "supervisor",
        lambda state: state["next_destination"],
        {
            "Backend_Coder": "Backend_Coder",
            "UI_Artist": "UI_Artist",
            "Tester_QA": "Tester_QA",
            "FINISH": END
        }
    )
    
    workflow.set_entry_point("supervisor")
    
    import sqlite3
    
    # Establish a persistent connection to the SQLite database file
    conn = sqlite3.connect(str(CHECKPOINT_DB), check_same_thread=False)
    checkpointer = SqliteSaver(conn)
    
    return workflow.compile(checkpointer=checkpointer)

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          P U B L I C   A P I                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

def run_autonomous_team(
    task: str,
    *,
    thread_id: Optional[str] = None,
    resume: bool = False,
) -> str:
    """Invoke the overnight coding team on the given task.

    Parameters
    ----------
    task : str
        High-level project requirement to implement.
    thread_id : str | None
        Stable id for checkpointing.  If ``resume`` is True and no id is
        given, the most-recent thread is used.
    resume : bool
        If True, resume the last checkpointed run rather than starting fresh.

    Returns
    -------
    str
        Final agent output — milestone summary, commit list, or error report.
    """

    if resume and thread_id is None:
        thread_id = _latest_thread_id()
        if thread_id is None:
            return "No previous run found to resume. Start a new task instead."

    thread_id = thread_id or f"task-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

    initial_state: TeamState = {
        "messages": [
            HumanMessage(
                content=(
                    f"<PROJECT_REQUIREMENT>\n{task}\n</PROJECT_REQUIREMENT>\n\n"
                    f"Workspace root: {WORKSPACE_PATH}\n"
                    "Begin by planning milestones then delegating to workers."
                )
            )
        ],
        "task_description": task,
        "project_root": str(WORKSPACE_PATH),
        "next_destination": "supervisor",  # Seed the initial destination tracker
    }

    config = {
        "configurable": {"thread_id": thread_id},
        "recursion_limit": RECURSION_LIMIT + 10,  # supervisor wrapper overhead
    }

    print(f"\n{'═'*70}")
    print(f"  THREAD  : {thread_id}")
    print(f"  TASK    : {task[:80]}{'...' if len(task) > 80 else ''}")
    print(f"  CHECKPT : {CHECKPOINT_DB}")
    print(f"  LIMIT   : {RECURSION_LIMIT} turns")
    print(f"{'═'*70}\n")

    try:
        result = _get_compiled_graph().invoke(initial_state, config=config)
    except Exception as exc:
        return (
            f"ORCHESTRATION HALTED — {exc}\n\n"
            f"To resume, call:\n"
            f"  run_autonomous_team(task=None, thread_id='{thread_id}', resume=True)"
        )

    messages: list = result.get("messages", [])
    last_ai = ""
    for m in reversed(messages):
        if isinstance(m, AIMessage) and m.content:
            last_ai = str(m.content)
            break

    return last_ai or "No final output produced."


def resume_last_run() -> str:
    """Convenience wrapper to resume the most-recent checkpoint."""
    return run_autonomous_team(task="(resume)", resume=True)


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          H E L P E R S                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

def _latest_thread_id() -> Optional[str]:
    """Return the thread_id of the most-recent checkpoint, if any.

    Falls back gracefully if the DB schema changes or the file is absent.
    """
    if not CHECKPOINT_DB.exists():
        return None
    try:
        import sqlite3
        conn = sqlite3.connect(str(CHECKPOINT_DB))
        cur = conn.execute(
            "SELECT thread_id FROM checkpoints ORDER BY checkpoint_id DESC LIMIT 1"
        )
        row = cur.fetchone()
        conn.close()
        return row[0] if row else None
    except Exception:
        return None  # schema changed, DB locked, etc. — not critical


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          M A I N                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if __name__ == "__main__":
    TASK_PROMPT = (
        "Initialize the 'Open Cowork' v0.1 Foundation project.\n\n"
        "CONTEXT from proposal.md: Build an open-source Mac AI desktop agent "
        "— a menubar app with a floating chat panel that controls macOS via "
        "the Accessibility API (AXUIElement) and CGEvent for mouse/keyboard.\n\n"
        "DELIVERABLES:\n"
        "1. Python orchestrator skeleton with FastAPI endpoints (POST /task, "
        "GET /status, WebSocket /ws) inside a new 'orchestrator/' directory.\n"
        "2. Basic project structure: orchestrator/main.py, orchestrator/agent_loop.py, "
        "orchestrator/safety.py, orchestrator/cost_tracker.py, orchestrator/storage.py, "
        "orchestrator/providers/ (anthropic.py, openai.py, ollama.py).\n"
        "3. requirements.txt with fastapi, uvicorn, websockets, and any needed deps.\n"
        "4. Ensure every .py file has a proper module docstring and clean imports.\n"
        "5. The Tester must verify each file is syntactically valid Python.\n\n"
        "Conventional Commits required (feat:, fix:, chore:)."
    )

    if len(sys.argv) > 1:
        TASK_PROMPT = " ".join(sys.argv[1:])

    print("🚀 Launching Autonomous Coding Team (LangGraph Supervisor Pattern)\n")
    output = run_autonomous_team(TASK_PROMPT)
    print(f"\n{'─'*70}")
    print("FINAL OUTPUT:")
    print(output)
    print(f"{'─'*70}")
