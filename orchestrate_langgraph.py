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

RECURSION_LIMIT = 5000
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
        return f"COMMITTED: {hash_result.stdout.strip()} -- {commit_message}"
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
        "You are the Backend Coder for the Open Cowork project. You MUST use tools "
        "to write code to disk. You CANNOT create files by describing them in text.\n\n"
        "SKILLS - CHECK BEFORE CODING:\n"
        "1. Call list_workspace_tool(path=\".opencode/skill\") to discover available skills.\n"
        "2. For each skill relevant to your backend task (e.g. react-native-best-practices,\n"
        "   upgrading-react-native, react-native-brownfield-migration, github, github-actions,\n"
        "   macos-menubar-tuist-app), read its SKILL.md:\n"
        "   file_read_tool(path=\".opencode/skill/<skill-name>/SKILL.md\")\n"
        "3. Apply the patterns and guidelines from those skills in your implementation.\n\n"
        "CRITICAL DIRECTIVES:\n"
        "1. INVOKE file_write_tool for EVERY file you create. Do not just describe the code.\n"
        "2. Use list_workspace_tool first to see what exists before making assumptions.\n"
        "3. After writing each file, the tool will return confirmation like "
        "\"OK: wrote 512 bytes to 'filename'.\" Wait for that confirmation.\n"
        "4. If you are writing multiple files, write them one at a time.\n"
        "5. NEVER say \"I have created the files\" unless the tool has confirmed each write.\n\n"
        "CORRECT PATTERN - FOLLOW THIS EXACTLY:\n"
        "  Step 1: list_workspace_tool(path=\".\")   -- see what exists\n"
        "  Step 2: list_workspace_tool(path=\".opencode/skill\")   -- discover relevant skills\n"
        "  Step 3: file_read_tool(path=\".opencode/skill/<name>/SKILL.md\")   -- read relevant skill\n"
        "  Step 4: file_write_tool(path=\"orchestrator/main.py\", content=\"from fastapi import FastAPI\\n...\")   -- write file\n"
        "  Step 5: Wait for tool to confirm: \"OK: wrote N bytes to 'orchestrator/main.py'.\"\n"
        "  Step 6: file_write_tool(path=\"orchestrator/__init__.py\", content=\"# package\\n\")   -- write next file\n"
        "  Step 7: Repeat for all required files.\n"
        "  Step 8: Only then say \"All files written.\"\n\n"
        "FAILURE MODE - NEVER DO THIS:\n"
        "  Writing code in your chat message and saying \"I created the file.\" "
        "This does NOT actually write anything to disk."
    ),
    name="Backend_Coder",
)

ui_artist = create_react_agent(
    model=_build_llm(UI_ARTIST_KEY, WORKER_MODEL, temperature=0.3),
    tools=[file_read_tool, file_write_tool, list_workspace_tool],
    prompt=(
        "You are the UI Artist for the Open Cowork project. You MUST use tools "
        "to write UI code to disk. You CANNOT create files by describing them in text.\n\n"
        "SKILLS - CHECK BEFORE CODING:\n"
        "1. Call list_workspace_tool(path=\".opencode/skill\") to discover available skills.\n"
        "2. For each UI-relevant skill, read its SKILL.md:\n"
        "   - swiftui-ui-patterns: SwiftUI patterns, navigation, layouts, sheets, menus\n"
        "   - swiftui-liquid-glass: iOS 26+ Liquid Glass glassmorphism API\n"
        "   - macos-menubar-tuist-app: macOS menubar app patterns, Tuist manifests, run scripts\n"
        "   - react-native-best-practices: RN performance, FPS, bundle, animations (if React Native)\n"
        "   Use: file_read_tool(path=\".opencode/skill/<skill-name>/SKILL.md\")\n"
        "3. Apply the design patterns, conventions, and code snippets from those skills.\n\n"
        "CRITICAL DIRECTIVES:\n"
        "1. INVOKE file_write_tool for EVERY file you create or modify. Do not just describe the code.\n"
        "2. Use file_read_tool first to read existing UI files and match conventions.\n"
        "3. After writing each file, the tool will return confirmation like "
        "\"OK: wrote 512 bytes to 'filename'.\" Wait for that confirmation.\n"
        "4. If you are writing multiple files, write them one at a time.\n"
        "5. NEVER say \"I have updated the UI\" unless the tool has confirmed each write.\n\n"
        "CORRECT PATTERN - FOLLOW THIS EXACTLY:\n"
        "  Step 1: list_workspace_tool(path=\".opencode/skill\")   -- discover UI skills\n"
        "  Step 2: file_read_tool(path=\".opencode/skill/swiftui-ui-patterns/SKILL.md\")   -- read patterns\n"
        "  Step 3: file_read_tool(path=\"orchestrator/main.py\")   -- read existing files first\n"
        "  Step 4: file_write_tool(path=\"orchestrator/static/style.css\", content=\"body { font-family: sans-serif; }\\n\")   -- write UI file\n"
        "  Step 5: Wait for tool to confirm: \"OK: wrote N bytes to 'orchestrator/static/style.css'.\"\n"
        "  Step 6: file_write_tool(path=\"orchestrator/templates/index.html\", content=\"<!DOCTYPE html>\\n<html>...\")   -- write next file\n"
        "  Step 7: Repeat for all required files.\n"
        "  Step 8: Only then say \"All UI files written.\"\n\n"
        "FAILURE MODE - NEVER DO THIS:\n"
        "  Writing HTML/CSS code in your chat message and saying \"I created the UI.\" "
        "This does NOT actually write anything to disk."
    ),
    name="UI_Artist",
)

tester_qa = create_react_agent(
    model=_build_llm(TESTER_KEY, WORKER_MODEL, temperature=0.0),
    tools=[shell_tool, file_read_tool, list_workspace_tool, git_snapshot_tool],
    prompt=(
        "You are the Tester / QA for the Open Cowork project. You are a strict, "
        "skeptical quality gatekeeper. You MUST use tools to verify code — you "
        "CANNOT trust claims made in chat messages.\n\n"
        "SKILLS - CHECK BEFORE TESTING:\n"
        "1. Call list_workspace_tool(path=\".opencode/skill\") to discover available skills.\n"
        "2. For relevant testing/CI skills, read their SKILL.md:\n"
        "   - github: PR workflows, commit conventions, stacked PR merge patterns\n"
        "   - github-actions: CI build artifact patterns for testing\n"
        "   Use: file_read_tool(path=\".opencode/skill/<skill-name>/SKILL.md\")\n"
        "3. Apply the patterns from those skills when verifying commits and CI workflows.\n\n"
        "CRITICAL DIRECTIVES:\n"
        "1. NEVER TRUST, ALWAYS VERIFY: Do not trust the Coder when they say they wrote "
        "a file. Use `list_workspace_tool` to check files actually exist on disk.\n"
        "2. You CANNOT verify code by reading it. You MUST invoke `shell_tool` to "
        "actually run `python3 -m py_compile <file>` for Python files.\n"
        "3. After the tool returns EXIT: 0 for all files, you MUST call "
        "`git_snapshot_tool` to commit the code with a Conventional Commits message.\n"
        "4. ONLY reply with the exact phrase \"ALL CHECKS PASSED -- COMMITTED\" after "
        "the git_snapshot_tool returns a hash like \"COMMITTED: abc1234 -- feat: ...\".\n"
        "5. If files are missing or any check fails, report the errors and DO NOT commit.\n\n"
        "CORRECT PATTERN - FOLLOW THIS EXACTLY:\n"
        "  Step 1: list_workspace_tool(path=\".opencode/skill\")   -- discover skills\n"
        "  Step 2: list_workspace_tool(path=\"orchestrator\")   -- verify files exist\n"
        "  Step 3: shell_tool(command=\"python3 -m py_compile orchestrator/main.py\")   -- check syntax\n"
        "  Step 4: Check output for \"EXIT: 0\" -- if errors found, report them and STOP.\n"
        "  Step 5: shell_tool(command=\"python3 -m py_compile orchestrator/__init__.py\")   -- check next file\n"
        "  Step 6: After ALL files pass (EXIT: 0), call:\n"
        "    git_snapshot_tool(commit_message=\"feat: add orchestrator skeleton\")\n"
        "  Step 7: Wait for the tool to return \"COMMITTED: <hash> -- feat: ...\"\n"
        "  Step 8: Then reply: \"ALL CHECKS PASSED -- COMMITTED\"\n\n"
        "FAILURE MODE - NEVER DO THIS:\n"
        "  Saying \"All files look good, committing now.\" in your chat message. "
        "You MUST actually invoke git_snapshot_tool and wait for its response."
    ),
    name="Tester_QA",
)

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     S U P E R V I S O R   L O O P                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

supervisor_agent = create_react_agent(
    model=_build_llm(MANAGER_API_KEY, MANAGER_MODEL, temperature=0.2),
    tools=[file_read_tool, list_workspace_tool],
    prompt=(
        "You are the Project Manager / Supervisor of an autonomous coding "
        "team. Your job is to take a high-level project requirement and "
        "orchestrate its implementation through your workers.\n\n"
        "AVAILABLE TOOLS:\n"
        "- file_read_tool(path): Read a file's contents.\n"
        "- list_workspace_tool(path): List files/directories in the workspace.\n\n"
        "CRITICAL -- YOUR FIRST TURN:\n"
        "1. Call file_read_tool(\"proposal.md\") to read the full project proposal.\n"
        "2. Call list_workspace_tool(\".\") to see what already exists.\n"
        "3. Call list_workspace_tool(path=\".opencode/skill\") to discover available skills.\n"
        "4. For each relevant skill, read its SKILL.md using:\n"
        "   file_read_tool(path=\".opencode/skill/<skill-name>/SKILL.md\")\n"
        "   Key skills to check:\n"
        "   - macos-menubar-tuist-app: macOS menubar app patterns (directly relevant!)\n"
        "   - swiftui-ui-patterns: SwiftUI UI patterns for any native UI work\n"
        "   - swiftui-liquid-glass: iOS 26+ Liquid Glass UI effects\n"
        "   - react-native-best-practices: RN performance optimization\n"
        "   - github: GitHub PR and commit conventions\n"
        "   - github-actions: CI build artifact patterns\n"
        "5. Break the task into clear milestones, referencing the skills each worker should use.\n"
        "6. When delegating to a worker, tell them which skills to read.\n\n"
        "YOUR WORKERS:\n"
        "- Backend_Coder: writes application logic, data models, APIs, core code.\n"
        "- UI_Artist: handles visual presentation, styles, templates, front-end.\n"
        "- Tester_QA: runs compilers, linters, test suites AND creates git commits "
        "when all checks pass.\n\n"
        "WORKFLOW:\n"
        "1. Break the task into clear milestones (share them in your first message).\n"
        "2. For each milestone, delegate to the appropriate worker and tell them which skills to use.\n"
        "3. After EVERY code change, delegate to Tester_QA for verification.\n"
        "4. If Tester_QA reports failures, send the error feedback back to the "
        "coder that made the changes.\n"
        "5. If Tester_QA reports \"ALL CHECKS PASSED -- COMMITTED\", move to "
        "the next milestone.\n"
        "6. Continue until all milestones are complete.\n\n"
        "CRITICAL:\n"
        "- Never delegate to two workers simultaneously -- sequential only.\n"
        "- Never skip the Tester_QA step after code changes.\n"
        "- When the project is fully complete, respond with \"PROJECT COMPLETE\".\n"
        "- **You MUST read proposal.md and .opencode/skill/** using file_read_tool -- do NOT guess contents.\n\n"
        "IMPORTANT: You MUST append a raw JSON block on its own line at the very "
        "end of your final reply (after all milestones / planning text):\n"
        '{"next_step": "Backend_Coder"}   (Choose strictly from: "Backend_Coder", "UI_Artist", "Tester_QA", "FINISH")'
    ),
    name="Supervisor",
)


def supervisor_node(state: TeamState):
    """Invoke the supervisor ReAct agent (with tools for reading files / listing
    workspace), parse the routing JSON from its output, and return the next destination."""
    import time

    # Rate-limited invoke of the supervisor agent
    for attempt in range(1, 51):
        try:
            response = supervisor_agent.invoke(state)
            break
        except Exception as exc:
            wait = min(10 * (1.5 ** (attempt - 1)), 120)
            print(f"⚠️  [Supervisor] Error (attempt {attempt}/50): {exc}")
            print(f"⏳  Retrying in {wait:.0f}s...")
            time.sleep(wait)
    else:
        raise RuntimeError("Supervisor failed after 50 attempts.")

    # Extract routing decision from the LAST AIMessage that has content
    next_step = "Tester_QA"  # safe default
    for msg in reversed(response["messages"]):
        if isinstance(msg, AIMessage) and msg.content:
            content = msg.content.strip()
            start = content.rfind("{")
            if start != -1:
                end = content.find("}", start)
                if end != -1:
                    try:
                        parsed = json.loads(content[start:end + 1])
                        candidate = parsed.get("next_step")
                        if candidate in ["Backend_Coder", "UI_Artist", "Tester_QA", "FINISH"]:
                            next_step = candidate
                    except Exception:
                        pass
            break

    # Safety Guard: prevent premature FINISH before any tests pass
    has_passed_tests = any(
        "ALL CHECKS PASSED" in getattr(m, "content", "") for m in response["messages"]
    )
    if next_step == "FINISH" and not has_passed_tests:
        next_step = "Tester_QA"

    return {
        "messages": response["messages"],
        "next_destination": next_step,
    }


@functools.lru_cache(maxsize=1)
def _get_compiled_graph():
    """Build and compile the multi-agent state graph using 0.6.x syntax."""
    from langgraph.graph import StateGraph, END
    
    workflow = StateGraph(TeamState)
    
    def _rate_limited_invoke(agent, label: str, state: TeamState):
        """Invoke *agent* with retry on API rate limits and explicitly reset routing state."""
        import time
        for attempt in range(1, 51):
            try:
                response = agent.invoke(state)
                return {
                    "messages": response["messages"],
                    "next_destination": "supervisor"
                }
            except Exception as exc:
                wait = min(10 * (1.5 ** (attempt - 1)), 120)
                print(f"⚠️  [{label}] Error (attempt {attempt}/50): {exc}")
                print(f"⏳  Retrying in {wait:.0f}s...")
                time.sleep(wait)
        raise RuntimeError(f"{label} failed after 50 attempts.")

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
# ╚══════════════════════════════════════════════════════════════════════════════╝

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
    if not resume:
        _clean_stale_outputs()

    print(f"{'═'*70}\n")

    try:
        print("🤖 [System] Standing up OpenRouter agent communication lines...\n")
        
        previous_msg_count = 0
        for event in _get_compiled_graph().stream(initial_state, config=config, stream_mode="values"):
            if "messages" in event and event["messages"]:
                latest_message = event["messages"][-1]
                sender = getattr(latest_message, "name", None) or latest_message.__class__.__name__
                if sender == "HumanMessage":
                    continue
                
                print(f"\n🔹 [\033[1;34m{sender}\033[0m]")
                if latest_message.content:
                    print(f"{latest_message.content}")
                
                # Scan only NEW messages for tool calls (not the last message only, and not old ones)
                # The ReAct agent produces multiple messages per node invocation:
                # AIMessage(tool_calls) -> ToolMessage -> AIMessage(final text)
                # Tool calls are in earlier messages, NOT in the final text message.
                # Track message count to avoid re-scanning old messages on future events.
                for msg in event["messages"][previous_msg_count:]:
                    if hasattr(msg, "tool_calls") and msg.tool_calls:
                        for tool_call in msg.tool_calls:
                            print(f"🛠️  \033[0;33mUsing Tool:\033[0m {tool_call['name']}")
                previous_msg_count = len(event["messages"])
                        
        result = _get_compiled_graph().get_state(config).values
    except Exception as exc:
        return (
            f"ORCHESTRATION HALTED -- {exc}\n\n"
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


def _clean_stale_outputs() -> None:
    """Delete previously-generated orchestrator files so the AI agents
    start from a clean slate.  Skips files outside the workspace."""
    import shutil
    targets = [
        WORKSPACE_PATH / "orchestrator",
        WORKSPACE_PATH / "requirements.txt",
    ]
    for t in targets:
        if t.is_dir():
            shutil.rmtree(t, ignore_errors=True)
            print(f"🧹 Removed stale directory: {t.name}/")
        elif t.is_file():
            t.unlink(missing_ok=True)
            print(f"🧹 Removed stale file: {t.name}")


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
        "-- a menubar app with a floating chat panel that controls macOS via "
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
