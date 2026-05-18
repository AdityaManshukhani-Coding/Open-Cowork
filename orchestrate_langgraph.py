from __future__ import annotations

import functools
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Annotated, List, Optional, TypedDict
from langgraph.graph.message import add_messages

# ─────────────────────────────────────────────────────────────────────────────
# API CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

OPENROUTER_API_BASE = "https://openrouter.ai/api/v1"

MANAGER_API_KEY = os.environ.get(
    "OPENROUTER_MANAGER_KEY",
    "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",
)
BACKEND_CODER_KEY = os.environ.get(
    "OPENROUTER_BACKEND_KEY",
    "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",
)
UI_ARTIST_KEY = os.environ.get(
    "OPENROUTER_UI_KEY",
    "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",
)
TESTER_KEY = os.environ.get(
    "OPENROUTER_TESTER_KEY",
    "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",
)

MANAGER_MODEL = "deepseek/deepseek-v4-flash:free"
WORKER_MODEL = "deepseek/deepseek-v4-flash:free"

# ─────────────────────────────────────────────────────────────────────────────
# RESILIENCE SETTINGS
# ─────────────────────────────────────────────────────────────────────────────

RECURSION_LIMIT = 400
os.environ.setdefault("LITELLM_NUM_RETRIES", "1000")
os.environ.setdefault("LITELLM_MAX_RETRY_DELAY", "90")
os.environ.setdefault("LITELLM_REQUEST_TIMEOUT", "300")

# ─────────────────────────────────────────────────────────────────────────────
# WORKSPACE — the main Open Cowork project directory
# ─────────────────────────────────────────────────────────────────────────────

WORKSPACE_PATH = Path(__file__).resolve().parent
CHECKPOINT_DB = WORKSPACE_PATH / "agent_checkpoints.db"

# ─────────────────────────────────────────────────────────────────────────────
# IMPORTS
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
    messages: Annotated[List[BaseMessage], add_messages]
    task_description: str
    project_root: str
    next_destination: str


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
    """Return a ChatOpenAI instance pointed at OpenRouter with clean tracking headers."""
    return ChatOpenAI(
        api_key=api_key,
        base_url=OPENROUTER_API_BASE,
        model=model,
        temperature=temperature,
        max_tokens=4096, 
        timeout=90,
        max_retries=1000,
        default_headers={
            "HTTP-Referer": "https://github.com/aditya-manshukhani/open-cowork", 
            "X-Title": "Open Cowork Orchestrator"
        }
    )


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     W O R K E R   A G E N T S                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

backend_coder = create_react_agent(
    model=_build_llm(BACKEND_CODER_KEY, WORKER_MODEL, temperature=0.1),
    tools=[file_read_tool, file_write_tool, shell_tool, list_workspace_tool],
    prompt=(
        "You are the Backend Coder for the Open Cowork project. You are a system agent that MUST use tools to interact with the environment.\n\n"
        "CRITICAL DIRECTIVES - READ CAREFULLY:\n"
        "1. NO PRETENDING: You CANNOT create files by just typing code in your chat response. You MUST explicitly invoke the `file_write_tool` to save code to the disk.\n"
        "2. VERIFY REALITY: Always use `list_workspace_tool` to see what actually exists in the directory before assuming files are there.\n"
        "3. DO THE WORK: If you are asked to initialize a project or write a script, you must actively call `file_write_tool` for EVERY single file required in the deliverables.\n"
        "4. NEVER say you have completed a task unless you have successfully executed the tool calls to write the files."
    ),
    name="Backend_Coder",
)

ui_artist = create_react_agent(
    model=_build_llm(UI_ARTIST_KEY, WORKER_MODEL, temperature=0.3),
    tools=[file_read_tool, file_write_tool, list_workspace_tool],
    prompt=(
        "You are the UI Artist. You operate entirely through tool invocations.\n\n"
        "CRITICAL DIRECTIVES:\n"
        "1. Always read existing UI files first to match conventions using `file_read_tool`.\n"
        "2. You MUST use `file_write_tool` for all changes. Do not output code directly to the user.\n"
        "3. Report every file you modify only AFTER the tool confirms it was written."
    ),
    name="UI_Artist",
)

tester_qa = create_react_agent(
    model=_build_llm(TESTER_KEY, WORKER_MODEL, temperature=0.0),
    tools=[shell_tool, file_read_tool, list_workspace_tool, git_snapshot_tool],
    prompt=(
        "You are the Tester / QA. You are a strict, skeptical quality gatekeeper.\n\n"
        "CRITICAL DIRECTIVES - READ CAREFULLY:\n"
        "1. NEVER TRUST, ALWAYS VERIFY: Do not trust the Coder when they say they wrote a file. You MUST use `list_workspace_tool` to verify the files actually exist on the disk.\n"
        "2. NO HALLUCINATIONS: You CANNOT verify code syntax by just reading it in chat. You MUST invoke `shell_tool` with the command `python3 -m py_compile <file>` for Python files.\n"
        "3. COMMIT THE CODE: If and ONLY if the `shell_tool` returns zero errors for the files, you MUST invoke `git_snapshot_tool` to commit the code.\n"
        "4. ONLY reply with the exact phrase \"ALL CHECKS PASSED — COMMITTED\" after you see the successful commit hash returned by the git tool. If files are missing or errors occur, report them and DO NOT commit."
    ),
    name="Tester_QA",
)

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     S U P E R V I S O R   G R A P H                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

def supervisor_node(state: TeamState):
    """Manual supervisor implementation using text-parsed JSON routing to handle
    non-functional free-tier constraints safely.
    """
    llm = _build_llm(MANAGER_API_KEY, MANAGER_MODEL, temperature=0.2)
    
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
        "- When the project is fully complete, respond with \"PROJECT COMPLETE\".\n\n"
        "IMPORTANT: You MUST append a raw JSON block tracking the next step on its own line at the absolute end of your reply:\n"
        '{"next_step": "Tester_QA"}   (Choose strictly from: "Backend_Coder", "UI_Artist", "Tester_QA", "FINISH")'
    )

    messages = [HumanMessage(content=system_prompt)] + state["messages"]
    response = llm.invoke(messages)
    content = response.content.strip()
    
    # Default fallback to testing layout if schema extraction trips
    next_step = "Tester_QA"
    
    start = content.rfind("{")
    if start != -1:
        end = content.find("}", start)
        if end != -1:
            try:
                parsed = json.loads(content[start:end+1])
                candidate = parsed.get("next_step")
                if candidate in ["Backend_Coder", "UI_Artist", "Tester_QA", "FINISH"]:
                    next_step = candidate
            except Exception:
                pass

    # Safety Guard: Intercept immediate exits before any QA confirmation passes
    has_passed_tests = any("ALL CHECKS PASSED" in getattr(m, "content", "") for m in state["messages"])
    if next_step == "FINISH" and not has_passed_tests:
        next_step = "Tester_QA"
    
    return {
        "messages": [AIMessage(content=f"Supervisor designated: {next_step}")],
        "next_destination": next_step
    }


@functools.lru_cache(maxsize=1)
def _get_compiled_graph():
    """Build and compile the multi-agent state graph using 0.6.x syntax."""
    from langgraph.graph import StateGraph, END
    
    workflow = StateGraph(TeamState)
    
    def _rate_limited_invoke(agent, label: str, state: TeamState):
        """Invoke *agent* with retry on API rate limits and explicitly reset routing state."""
        import time
        for attempt in range(1, 16):
            try:
                response = agent.invoke(state)
                return {
                    "messages": response["messages"],
                    "next_destination": "supervisor"
                }
            except Exception as exc:
                if "429" in str(exc) or "Too Many Requests" in str(exc):
                    wait = 90  
                    print(f"⚠️  [{label} Rate-Limited] Retrying ({attempt}/15) in {wait}s...")
                    time.sleep(wait)
                else:
                    raise exc
        raise RuntimeError(f"{label} failed after persistent rate limits.")

    def run_backend(state: TeamState):
        return _rate_limited_invoke(backend_coder, "Backend Coder", state)

    def run_ui(state: TeamState):
        return _rate_limited_invoke(ui_artist, "UI Artist", state)

    def run_tester(state: TeamState):
        return _rate_limited_invoke(tester_qa, "Tester QA", state)
    
    workflow.add_node("supervisor", supervisor_node)
    workflow.add_node("Backend_Coder", run_backend)
    workflow.add_node("UI_Artist", run_ui)
    workflow.add_node("Tester_QA", run_tester)
    
    workflow.add_edge("Backend_Coder", "supervisor")
    workflow.add_edge("UI_Artist", "supervisor")
    workflow.add_edge("Tester_QA", "supervisor")
    
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
    conn = sqlite3.connect(str(CHECKPOINT_DB), check_same_thread=False)
    checkpointer = SqliteSaver(conn)
    
    return workflow.compile(checkpointer=checkpointer)

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          P U B L I C   A P I                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╗

def run_autonomous_team(
    task: str,
    *,
    thread_id: Optional[str] = None,
    resume: bool = False,
) -> str:
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
        "next_destination": "supervisor", 
    }

    config = {
        "configurable": {"thread_id": thread_id},
        "recursion_limit": RECURSION_LIMIT + 10,  
    }

    print(f"\n{'═'*70}")
    print(f"  THREAD  : {thread_id}")
    print(f"  TASK    : {task[:80]}{'...' if len(task) > 80 else ''}")
    print(f"  CHECKPT : {CHECKPOINT_DB}")
    print(f"  LIMIT   : {RECURSION_LIMIT} turns")
    print(f"{'═'*70}\n")

    try:
        print("🤖 [System] Standing up OpenRouter agent communication lines...\n")
        
        for event in _get_compiled_graph().stream(initial_state, config=config, stream_mode="values"):
            if "messages" in event and event["messages"]:
                latest_message = event["messages"][-1]
                sender = getattr(latest_message, "name", latest_message.__class__.__name__)
                if sender == "HumanMessage":
                    continue
                
                print(f"\n🔹 [\033[1;34m{sender}\033[0m]")
                if latest_message.content:
                    print(f"{latest_message.content}")
                
                if hasattr(latest_message, "tool_calls") and latest_message.tool_calls:
                    for tool_call in latest_message.tool_calls:
                        print(f"🛠️  \033[0;33mUsing Tool:\033[0m {tool_call['name']}")
                        
        result = _get_compiled_graph().get_state(config).values
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


def _latest_thread_id() -> Optional[str]:
    """Return the thread_id of the most-recent checkpoint, if any."""
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
        return None


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