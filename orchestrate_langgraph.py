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
from langchain_core.messages import AIMessage, BaseMessage, HumanMessage, ToolMessage
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
    worker_retries: dict  # {worker_name: attempt_count} — tracks retries per worker
    last_verified_files: list  # files confirmed on disk


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
            timeout=300,  # 5 min — first swift build may download toolchain
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
        return "ERROR: command timed out after 300 s."
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
        max_tokens=8192,
        timeout=120,
        max_retries=1000,
        default_headers={
            "HTTP-Referer": "https://github.com/aditya-manshukhani/open-cowork",
            "X-Title": "Open Cowork Orchestrator"
        }
    )


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     V E R I F I C A T I O N   H E L P E R S                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝


def _worker_wrote_files(messages: list) -> bool:
    """Check whether any ToolMessage in the given message list confirms a
    successful file_write_tool call (content starting with \"OK: wrote\")."""
    for msg in messages:
        if isinstance(msg, ToolMessage) and msg.content and "OK: wrote" in str(msg.content):
            return True
    return False


def _last_worker(messages: list) -> str | None:
    """Return the name of the most-recent non-Supervisor worker that produced
    an AI message, or None if no such worker exists."""
    for msg in reversed(messages):
        name = getattr(msg, "name", None)
        if name in ("Backend_Coder", "UI_Artist", "Tester_QA"):
            return name
    return None


STUB_PATTERNS = [
    "TODO",
    "FIXME",
    "HACK",
    "<#",           # Xcode code-placeholder
    "// stub",
    "// placeholder",
    'fatalError("unimplemented"',
    'fatalError("not implemented"',
    'fatalError("TODO"',
    "throw NotImplementedError",
    "NotImplementedError",
    "raise NotImplementedError",
    "raise NotImplemented",
]


def _file_contains_stub(text: str) -> bool:
    """Scan file text for stub/placeholder patterns."""
    text_lower = text.lower()
    for pat in STUB_PATTERNS:
        if pat.lower() in text_lower:
            return True
    # Also catch standalone "..." as function body (Swift stubs)
    lines = text.split("\n")
    for line in lines:
        stripped = line.strip()
        if stripped == "..." and not stripped.startswith("//"):
            return True
    return False


def _content_is_substantial(messages: list) -> tuple[bool, list[str]]:
    """Check that files written by the most recent worker contain actual
    implementation code — not stubs, TODOs, or placeholder comments.

    Returns (all_substantial: bool, stub_file_paths: list[str]).
    """
    # 1. Extract file paths from ToolMessage confirmations
    stash_paths: list[str] = []
    for msg in messages:
        if isinstance(msg, ToolMessage) and "OK: wrote" in str(msg.content):
            content = str(msg.content)
            # Format: "OK: wrote N bytes to 'relative/path'."
            if "'" in content:
                path = content.split("'")[1]
                if path not in stash_paths:
                    stash_paths.append(path)

    # 2. Read each file and scan for stub patterns
    stub_files: list[str] = []
    for path in stash_paths:
        full = WORKSPACE_PATH / path
        if not full.exists():
            stub_files.append(path)  # file claimed but doesn't exist
            continue
        text = full.read_text(encoding="utf-8")
        if _file_contains_stub(text):
            stub_files.append(path)

    return len(stub_files) == 0, stub_files


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     W O R K E R   A G E N T S                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

backend_coder = create_react_agent(
    model=_build_llm(BACKEND_CODER_KEY, WORKER_MODEL, temperature=0.1),
    tools=[file_read_tool, file_write_tool, shell_tool, list_workspace_tool],
    prompt=(
        "You are the Backend Coder. You write production-quality Swift code.\n\n"
        "██████████████████████████████████████████████████████████████████████████████\n"
        "CRITICAL RULE -- READ THIS TWICE:\n"
        "YOU CANNOT CREATE FILES BY DESCRIBING THEM IN TEXT.\n"
        "You MUST use the file_write_tool to write every single file to disk.\n"
        "If you write code in your chat message, it does NOT create a file.\n"
        'The tool will return: "OK: wrote N bytes to \'path\'." -- wait for it.\n'
        "██████████████████████████████████████████████████████████████████████████████\n\n"
        "██████████████████████████████████████████████████████████████████████████████\n"
        "QUALITY RULE -- READ THIS TWICE:\n"
        "NO STUBS. NO TODOs. NO PLACEHOLDERS. NO '...' BODIES.\n"
        "EVERY function, enum, struct, and class MUST be FULLY IMPLEMENTED.\n"
        "The verification system DETECTS and REJECTS stub code.\n"
        "If the Manager asks for a component, write the COMPLETE implementation.\n"
        'You CANNOT leave anything unimplemented -- "TODO" is a FAILURE.\n'
        "██████████████████████████████████████████████████████████████████████████████\n\n"
        "CORRECT PATTERN -- FOLLOW THIS EXACTLY:\n"
        '  1. list_workspace_tool(path=".") -- see what exists\n'
        "  2. file_read_tool(path) -- read files you need to modify\n"
        "  3. file_write_tool(path=..., content=...) -- write the COMPLETE file\n"
        "  4. Wait for confirmation from file_write_tool: 'OK: wrote N bytes to ...'\n"
        "  5. Repeat for each file the manager asked for\n"
        '  6. shell_tool(command="swift build") -- verify it compiles\n'
        "  7. If swift build fails, fix errors and rebuild\n"
        "  8. Only after ALL files confirmed AND swift build passes, say 'All files written, compiles clean.'\n\n"
        "FAILURE MODES -- NEVER DO THESE:\n"
        "  - Writing code in your text message and saying 'I created the file.'\n"
        "    This does NOT write anything to disk.\n"
        "  - Writing an empty struct with '...' body or a function with TODO comment.\n"
        "    Every type must have all methods, properties, and logic fully written.\n\n"
        "IMPORTANT:\n"
        "- The Manager tells you exactly which file to create and its purpose.\n"
        "- Follow the Manager's instructions precisely.\n"
        "- If you need to know the tech stack or project layout, read existing\n"
        "  files (like Package.swift) first.\n"
        '- Use shell_tool(command="swift build") to compile after writing files.\n'
        "- If a dependency is needed, add it to Package.swift first, then run swift build.\n"
        "- Write SWIFT code for the macOS native app. Do NOT write Python unless the Manager explicitly asks for it."
    ),
    name="Backend_Coder",
)

ui_artist = create_react_agent(
    model=_build_llm(UI_ARTIST_KEY, WORKER_MODEL, temperature=0.3),
    tools=[file_read_tool, file_write_tool, list_workspace_tool, shell_tool],
    prompt=(
        "You are the UI Artist. You build native SwiftUI views for macOS using "
        "the **macOS 26 Tahu Liquid Glass** design language.\n\n"
        "██████████████████████████████████████████████████████████████████████████████\n"
        "CRITICAL RULE -- READ THIS TWICE:\n"
        "YOU CANNOT CREATE FILES BY DESCRIBING THEM IN TEXT.\n"
        "You MUST use the file_write_tool to write every single file to disk.\n"
        "If you write code in your chat message, it does NOT create a file.\n"
        'The tool will return: "OK: wrote N bytes to \'path\'." -- wait for it.\n'
        "██████████████████████████████████████████████████████████████████████████████\n\n"
        "██████████████████████████████████████████████████████████████████████████████\n"
        "QUALITY RULE -- READ THIS TWICE:\n"
        "NO STUBS. NO TODOs. NO PLACEHOLDERS. NO '...' BODIES.\n"
        "EVERY view, modifier, and interaction MUST be FULLY IMPLEMENTED.\n"
        "The verification system DETECTS and REJECTS stub code.\n"
        "Write COMPLETE, COMPILABLE SwiftUI views with all logic, state, and animations.\n"
        "██████████████████████████████████████████████████████████████████████████████\n\n"
        "██████████████████████████████████████████████████████████████████████████████\n"
        "macOS 26 TAHU LIQUID GLASS DESIGN LANGUAGE\n"
        "██████████████████████████████████████████████████████████████████████████████\n\n"
        "Use these native Liquid Glass APIs for ALL visual surfaces:\n\n"
        "1. BASIC GLASS SURFACE:\n"
        "   Text(\"Hello\")\n"
        "       .padding()\n"
        "       .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))\n\n"
        "2. GROUPED GLASS CONTAINER (use when multiple glass elements coexist):\n"
        "   GlassEffectContainer(spacing: 20) {\n"
        "       HStack(spacing: 20) {\n"
        "           Image(systemName: \"star.fill\")\n"
        "               .frame(width: 72, height: 72)\n"
        "               .glassEffect()\n"
        "           Image(systemName: \"heart.fill\")\n"
        "               .frame(width: 72, height: 72)\n"
        "               .glassEffect()\n"
        "       }\n"
        "   }\n\n"
        "3. GLASS BUTTONS:\n"
        "   Button(\"Confirm\") { /* action */ }\n"
        "       .buttonStyle(.glassProminent)\n"
        "   Button(\"Cancel\") { /* action */ }\n"
        "       .buttonStyle(.glass)\n\n"
        "4. MORPHING TRANSITIONS (when views appear/disappear):\n"
        '   @Namespace private var namespace\n'
        '   .glassEffectID("unique-id", in: namespace)\n\n'
        "5. TINTED GLASS for prominence:\n"
        "   .glassEffect(.regular.tint(.accentColor).interactive())\n\n"
        "6. FALLBACK for macOS < 26:\n"
        "   if #available(macOS 26, *) {\n"
        "       // Liquid Glass version\n"
        "   } else {\n"
        "       // UltraThinMaterial fallback\n"
        "       .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))\n"
        "   }\n\n"
        "Key design principles:\n"
        "- Views feel like floating glass panels with depth\n"
        "- Use subtle color tints (accentColor or theme colors)\n"
        "- Interactive glass for tappable/focusable elements\n"
        "- Consistent corner radii across related elements\n"
        "- GlassEffectContainer for grouping related glass views\n"
        "- Smooth transitions and fluid animations\n\n"
        "██████████████████████████████████████████████████████████████████████████████\n\n"
        "IMPORTANT:\n"
        "- This is a NATIVE macOS app (SwiftUI), NOT a web page.\n"
        "- Do NOT create HTML, CSS, or JavaScript files.\n"
        "- Follow the Manager's specific instructions for what to build.\n"
        "- Read existing files first to understand the project.\n"
        "- Use file_write_tool for every file. Wait for tool confirmation.\n"
        "- Use shell_tool to verify views compile with swift build.\n"
        "- Use native SwiftUI components (MenuBarExtra, List, TextField, Button).\n"
        "- If the Manager assigns a UI task, the view MUST use Liquid Glass APIs."
    ),
    name="UI_Artist",
)

tester_qa = create_react_agent(
    model=_build_llm(TESTER_KEY, WORKER_MODEL, temperature=0.0),
    tools=[shell_tool, file_read_tool, list_workspace_tool, file_write_tool, git_snapshot_tool],
    prompt=(
        "You are the Tester / QA for the Open Cowork project. You are a strict, "
        "skeptical quality gatekeeper. You MUST use tools to verify code - you "
        "CANNOT trust claims made in chat messages.\n\n"
        "██████████████████████████████████████████████████████████████████████████████\n"
        "CRITICAL RULE -- VERIFY BEFORE TRUSTING:\n"
        "Do NOT trust the Coder when they say they wrote a file.\n"
        "Use list_workspace_tool to check files actually exist on disk.\n"
        "Use file_read_tool to read their contents.\n"
        "██████████████████████████████████████████████████████████████████████████████\n\n"
        "██████████████████████████████████████████████████████████████████████████████\n"
        "ADDITIONAL -- CHECK FOR STUB CODE:\n"
        "Even if files exist, they may be STUBS (TODO, FIXME, NotImplementedError).\n"
        "Use file_read_tool to read each file and check for these patterns:\n"
        '- "TODO", "FIXME", "NotImplementedError"\n'
        "- Empty function bodies with '...'\n"
        "- Standalone \"fatalError(\"unimplemented\")\"\n"
        "If you find any, route back to the Coder with: 'Stub code found in <file>: <pattern>'\n"
        "██████████████████████████████████████████████████████████████████████████████\n\n"
        "YOUR TOOLS:\n"
        "- list_workspace_tool(path): Check files exist on disk.\n"
        "- file_read_tool(path): Read file contents to verify.\n"
        "- file_write_tool(path, content): Write files (use ONLY if files are missing -- as fallback).\n"
        "- shell_tool(command): Run compilers, linters, syntax checks, swift build.\n"
        "- git_snapshot_tool(message): Commit verified code.\n\n"
        'CORRECT PATTERN -- FOLLOW THIS EXACTLY:\n'
        '  Step 1: list_workspace_tool(path="Sources") -- verify Swift source files exist\n'
        '  Step 2: list_workspace_tool(path="Package.swift") -- verify SPM manifest exists\n'
        "  Step 3: file_read_tool to check each file for stub code patterns\n"
        '  Step 4: shell_tool(command="swift build") -- compile Swift project\n'
        "  Step 5: Check output for EXIT: 0 -- if errors, report them and DO NOT commit\n"
        '  Step 6: If Python files exist, shell_tool(command="python3 -m py_compile *.py") -- syntax check\n'
        "  Step 7: After ALL files pass, call:\n"
        '    git_snapshot_tool(commit_message="feat: add milestone description")\n'
        "  Step 8: Wait for 'COMMITTED: <hash> -- feat: ...' response\n"
        "  Step 9: Reply: 'ALL CHECKS PASSED -- COMMITTED'\n\n"
        "FALLBACK -- IF FILES ARE MISSING OR HAVE STUBS:\n"
        "  If the Coder didn't write files, you MAY write them yourself using\n"
        "  file_write_tool as a last resort. Then verify and commit.\n\n"
        "FAILURE MODE:\n"
        '  Saying "All files look good." without calling shell_tool or git_snapshot_tool.\n'
        "  You MUST run actual verification commands."
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
        "You are the Project Manager. Your job is to read proposal.md, plan "
        "the entire app, and delegate ONE small task at a time to your workers, "
        "repeating until the whole app is built.\n\n"
        "AVAILABLE TOOLS:\n"
        "- file_read_tool(path): Read a file's contents.\n"
        "- list_workspace_tool(path): List files/directories in the workspace.\n\n"

        "═══════════════════════════════════════════════════════════════════════════\n"
        "DESIGN LANGUAGE -- macOS 26 Tahu Liquid Glass\n"
        "═══════════════════════════════════════════════════════════════════════════\n"
        "ALL UI views MUST use the macOS 26 Tahu Liquid Glass design language:\n"
        "- GlassEffectContainer for grouped glass elements\n"
        "- .glassEffect(.regular.tint(...).interactive()) for individual surfaces\n"
        "- .buttonStyle(.glassProminent) for primary buttons, .buttonStyle(.glass) for secondary\n"
        "- glassEffectID + @Namespace for morphing transitions\n"
        "- UltraThinMaterial fallback for macOS < 26\n"
        "When assigning UI_Artist tasks, always specify 'using Liquid Glass design language'\n\n"

        "═══════════════════════════════════════════════════════════════════════════\n"
        "TURN 1 -- YOUR VERY FIRST ACTIVATION\n"
        "═══════════════════════════════════════════════════════════════════════════\n"
        "This is your FIRST turn. You MUST:\n"
        '1. Call file_read_tool("proposal.md") -- read the full project proposal\n'
        '2. Call list_workspace_tool(path=".") -- see what already exists\n'
        "3. Break the entire app into small, concrete milestones with numbered tasks\n"
        "4. Output your FULL plan (all milestones, all tasks per milestone)\n"
        "5. Assign the VERY FIRST task of Milestone 1 to a worker\n\n"
        "YOUR FIRST MESSAGE MUST LOOK LIKE THIS:\n"
        "```\n"
        "I've read proposal.md. The project builds a macOS menubar AI agent.\n"
        "Here is my complete plan:\n\n"
        "Milestone 1: macOS menubar app scaffold with Liquid Glass UI\n"
        "  Task 1: Create Package.swift with Swift 6.0 tools version\n"
        "  Task 2: Create Sources/OpenCowork/OpenCoworkApp.swift with @main\n"
        "  Task 3: Create Sources/OpenCowork/ContentView.swift with MenuBarExtra\n"
        "  Task 4: Create Sources/OpenCowork/ChatPanelView.swift using Liquid Glass\n"
        "  Task 5: Verify with swift build\n\n"
        "Milestone 2: macOS Accessibility Control Layer\n"
        "  Task 6: Create AXUIElement wrapper...\n"
        "  ...\n\n"
        "Starting with Task 1: Create Package.swift.\n"
        "Backend_Coder, create Package.swift with tools-version 6.0, an executable "
        'target named OpenCowork, dependency on SwiftUI, and set the deployment '
        "target to macOS 14. Write it now.\n"
        "```\n"
        '{"next_step": "Backend_Coder"}\n\n'

        "═══════════════════════════════════════════════════════════════════════════\n"
        "SUBSEQUENT TURNS -- A WORKER JUST FINISHED\n"
        "═══════════════════════════════════════════════════════════════════════════\n"
        "A worker has reported back. You MUST follow this EXACT sequence:\n\n"
        "Step 1 -- ACKNOWLEDGE:\n"
        "  Read the worker's output. Say what they built.\n"
        '  Example: "Backend_Coder created Package.swift -- good work."\n\n'
        "Step 2 -- VERIFY:\n"
        '  Call list_workspace_tool(path=".") to check the file actually exists.\n'
        "  Example: list_workspace_tool shows Package.swift -- confirmed on disk.\n"
        "  If the file is MISSING, route BACK to the same worker:\n"
        '  "Package.swift is NOT on disk. You MUST use file_write_tool to '
        'write it. Talking about code does not create files. Try again NOW."\n'
        '  {"next_step": "Backend_Coder"}\n\n'
        "Step 3 -- UPDATE PROGRESS:\n"
        "  Show what's been done and what's next:\n"
        "  Completed: [Task 1: Package.swift]\n"
        "  Remaining: [Task 2: OpenCoworkApp.swift, Task 3: ContentView.swift, ...]\n"
        "  Current milestone: Milestone 1 -- macOS menubar app scaffold\n\n"
        "Step 4 -- ASSIGN NEXT TASK:\n"
        "  Tell the worker EXACTLY what file to create and what it should contain.\n"
        "  IMPORTANT: Always require COMPLETE implementations -- no stubs, no TODOs.\n"
        '  Example: "Task 2: Create Sources/OpenCowork/OpenCoworkApp.swift. '
        "This is the @main entry point. It should import SwiftUI, define an App "
        "struct with @main that uses WindowGroup, and call "
        "NSApplication.shared.setActivationPolicy(.accessory) in its init() to "
        "make it a menubar-only app. Write the COMPLETE implementation -- "
        'every method, every property, no TODOs. Backend_Coder, write this file now."\n'
        '  {"next_step": "Backend_Coder"}\n\n'

        "For UI tasks, ALWAYS mention the Liquid Glass design language:\n"
        '  Example: "Task 4: Create Sources/OpenCowork/ChatPanelView.swift using '
        "macOS 26 Tahu Liquid Glass design. Use GlassEffectContainer for the panel, "
        "glassEffect with interactive() for the chat area, .glassProminent for the "
        "send button, and a tinted glass style for the header. Write the COMPLETE "
        'view with all state management -- no stubs."\n\n'

        "═══════════════════════════════════════════════════════════════════════════\n"
        "MILESTONE COMPLETE -- ROUTE TO TESTER_QA\n"
        "═══════════════════════════════════════════════════════════════════════════\n"
        "When all tasks in a milestone are done:\n"
        '- Say: "Milestone 1 complete. Tester_QA, please run swift build and commit."\n'
        "- Route to Tester_QA\n"
        '  {"next_step": "Tester_QA"}\n\n'
        "If Tester_QA reports compilation errors, route BACK to the coder:\n"
        '- "swift build failed with: <error>. Backend_Coder, fix these errors."\n'
        '  {"next_step": "Backend_Coder"}\n\n'
        'If Tester_QA says "ALL CHECKS PASSED -- COMMITTED":\n'
        '- "Committed at <hash>. Moving to next milestone."\n'
        "- Assign task 1 of milestone 2.\n\n"

        "═══════════════════════════════════════════════════════════════════════════\n"
        "YOUR WORKERS\n"
        "═══════════════════════════════════════════════════════════════════════════\n"
        "- Backend_Coder: writes code files (Swift, Python, configs). Has "
        "file_write_tool, file_read_tool, shell_tool, list_workspace_tool.\n"
        "- UI_Artist: builds native SwiftUI views for macOS with Liquid Glass design. Has "
        "file_write_tool, file_read_tool, list_workspace_tool, shell_tool.\n"
        "- Tester_QA: runs swift build, verifies files (including checking for stub code), commits. Has "
        "shell_tool, file_read_tool, list_workspace_tool, git_snapshot_tool.\n\n"

        "═══════════════════════════════════════════════════════════════════════════\n"
        "TECH STACK REFERENCE\n"
        "═══════════════════════════════════════════════════════════════════════════\n"
        "- Swift 6 + SwiftUI for native macOS app\n"
        "- macOS 26 Tahu Liquid Glass design language (glassEffect, GlassEffectContainer)\n"
        "- Swift Package Manager (Package.swift) -- NO Tuist, use SPM\n"
        "- macOS menubar app: call setActivationPolicy(.accessory) in @main init()\n"
        "- Accessibility API: AXUIElement for finding UI elements\n"
        "- Mouse/keyboard: CGEvent for simulation\n"
        "- Screenshots: ScreenCaptureKit\n"
        "- Build: swift build, swift test\n"
        "- Python (FastAPI) only if backend orchestrator is needed\n\n"

        "═══════════════════════════════════════════════════════════════════════════\n"
        "CRITICAL RULES\n"
        "═══════════════════════════════════════════════════════════════════════════\n"
        "- NEVER assign more than ONE task per delegation.\n"
        '  WRONG: "Backend_Coder, create all the source files."\n'
        '  RIGHT: "Backend_Coder, create Sources/OpenCowork/OpenCoworkApp.swift."\n'
        "- ALWAYS use list_workspace_tool to verify after a worker claims success.\n"
        "- REQUIRE complete implementations -- explicitly tell workers 'no stubs, no TODOs'.\n"
        "- If a worker fails 3 times in a row, proceed to Tester_QA anyway.\n"
        "- Never skip Tester_QA between milestones.\n"
        "- Read proposal.md on your first turn -- do NOT guess its contents.\n"
        '- When EVERY milestone is done: "PROJECT COMPLETE" -> {"next_step": "FINISH"}\n\n'

        "IMPORTANT: You MUST append a raw JSON block at the very end of your "
        "final reply (after all text, on its own line):\n"
        '{"next_step": "Backend_Coder"}   (Choose from: "Backend_Coder", "UI_Artist", "Tester_QA", "FINISH")'
    ),
    name="Supervisor",
)


def supervisor_node(state: TeamState):
    """Invoke the supervisor ReAct agent (with tools for reading files / listing
    workspace), parse the routing JSON from its output, and return the next destination.

    Adds a VERIFICATION LAYER: if a worker claims success but no file_write_tool
    calls were made OR the written code contains stubs/TODOs, route back to the
    worker with corrective feedback instead of letting the hallucination pass."""
    import time

    # -- Rate-limited invoke of the supervisor agent --
    for attempt in range(1, 51):
        try:
            response = supervisor_agent.invoke(state)
            break
        except Exception as exc:
            wait = min(10 * (1.5 ** (attempt - 1)), 120)
            print(f"[Supervisor] Error (attempt {attempt}/50): {exc}")
            print(f"Retrying in {wait:.0f}s...")
            time.sleep(wait)
    else:
        raise RuntimeError("Supervisor failed after 50 attempts.")

    # -- Extract routing decision from the LAST AIMessage that has content --
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

    # -- Safety Guard: prevent premature FINISH before any tests pass --
    has_passed_tests = any(
        "ALL CHECKS PASSED" in getattr(m, "content", "") for m in response["messages"]
    )
    if next_step == "FINISH" and not has_passed_tests:
        next_step = "Tester_QA"

    # ==========================================================================
    # VERIFICATION LAYER -- Detect hallucinated tool calls AND stub code
    # ==========================================================================
    # Check (1) that the most recent worker actually called file_write_tool, and
    # (2) that the written files contain substantial code (not stubs/TODOs).
    #
    # Fires on EVERY route (not just Tester_QA) so that mid-milestone
    # hallucinations are caught before they cascade.
    worker_retries = dict(state.get("worker_retries", {}))

    if next_step != "FINISH":
        last_worker = _last_worker(response["messages"])
        files_written = _worker_wrote_files(response["messages"])

        # CASE 1: Worker claimed success but never called file_write_tool
        if last_worker and not files_written:
            attempt_count = worker_retries.get(last_worker, 0) + 1
            worker_retries[last_worker] = attempt_count

            if attempt_count <= 3:
                print(f"[Verifier] {last_worker} claimed success but NO file_write_tool calls found")
                print(f"Routing back to {last_worker} (attempt {attempt_count}/3) with corrective feedback...")

                correction_msg = HumanMessage(
                    content=(
                        f"[VERIFIER] CRITICAL FEEDBACK:\n"
                        f"You ({last_worker}) claimed to have created files, but the system detected "
                        f'that you did NOT call file_write_tool. Your chat message saying "I created '
                        f'the file" does NOT write anything to disk.\n\n'
                        f"YOU MUST USE THE file_write_tool TO WRITE FILES.\n"
                        f"Example:\n"
                        f'  file_write_tool(path="Sources/OpenCowork/MyFile.swift", '
                        f'content="the full file content here...import SwiftUI...")\n'
                        f"  -> Tool returns: OK: wrote N bytes to 'Sources/OpenCowork/MyFile.swift'.\n\n"
                        f"Do NOT describe the code in text. Actually CALL the tool.\n"
                        f"Write at least ONE file right now to prove you can do it."
                    ),
                    name="Verifier"
                )

                return {
                    "messages": [correction_msg],
                    "next_destination": last_worker,
                    "worker_retries": worker_retries,
                }
            else:
                print(f"[Verifier] {last_worker} failed after {attempt_count} attempts. Giving up and proceeding.")

        # CASE 2: Worker wrote files, but check if they are substantial (not stubs/TODOs)
        elif last_worker and files_written:
            all_substantial, stub_files = _content_is_substantial(response["messages"])
            if not all_substantial:
                attempt_count = worker_retries.get(last_worker, 0) + 1
                worker_retries[last_worker] = attempt_count

                if attempt_count <= 3:
                    print(f"[Verifier] {last_worker} wrote stubs in: {stub_files}")
                    print(f"Routing back for complete implementations (attempt {attempt_count}/3)...")

                    correction_msg = HumanMessage(
                        content=(
                            f"[VERIFIER] CRITICAL FEEDBACK:\n"
                            f"You ({last_worker}) wrote files that contain stub or placeholder code "
                            f"(TODO, FIXME, ... body, NotImplementedError, etc.): {stub_files}\n\n"
                            f"EVERY function and type MUST be FULLY IMPLEMENTED.\n"
                            f"The verification system detects and rejects stub code.\n"
                            f"Rewrite these files with COMPLETE, COMPILABLE implementations:\n"
                            f"  {', '.join(stub_files)}\n"
                            f"Then use shell_tool to compile with swift build.\n"
                            f"Do NOT leave anything unimplemented."
                        ),
                        name="Verifier"
                    )
                    return {
                        "messages": [correction_msg],
                        "next_destination": last_worker,
                        "worker_retries": worker_retries,
                    }
                else:
                    print(f"[Verifier] {last_worker} still writing stubs after {attempt_count} attempts. Giving up.")
            else:
                print(f"[Verifier] {last_worker} wrote substantial code. Proceeding.")

    return {
        "messages": response["messages"],
        "next_destination": next_step,
        "worker_retries": worker_retries,
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
                print(f"[{label}] Error (attempt {attempt}/50): {exc}")
                print(f"Retrying in {wait:.0f}s...")
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
        "worker_retries": {},
        "last_verified_files": [],
    }

    config = {
        "configurable": {"thread_id": thread_id},
        "recursion_limit": RECURSION_LIMIT + 10,
    }

    print(f"\n{'='*70}")
    print(f"  THREAD  : {thread_id}")
    print(f"  TASK    : {task[:80]}{'...' if len(task) > 80 else ''}")
    print(f"  CHECKPT : {CHECKPOINT_DB}")
    print(f"  LIMIT   : {RECURSION_LIMIT} turns")
    if not resume:
        _clean_stale_outputs()

    print(f"{'='*70}\n")

    try:
        print("[System] Standing up OpenRouter agent communication lines...\n")

        previous_msg_count = 0
        for event in _get_compiled_graph().stream(initial_state, config=config, stream_mode="values"):
            if "messages" in event and event["messages"]:
                latest_message = event["messages"][-1]
                sender = getattr(latest_message, "name", None) or latest_message.__class__.__name__
                if sender == "HumanMessage":
                    continue

                print(f"\n>> [{sender}]")
                if latest_message.content:
                    print(f"{latest_message.content}")

                for msg in event["messages"][previous_msg_count:]:
                    if hasattr(msg, "tool_calls") and msg.tool_calls:
                        for tool_call in msg.tool_calls:
                            print(f"  [Tool: {tool_call['name']}]")
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
    dirs = [
        WORKSPACE_PATH / "orchestrator",      # Python backend
        WORKSPACE_PATH / "Sources",            # Swift sources
        WORKSPACE_PATH / "Tests",              # Swift tests
        WORKSPACE_PATH / ".build",             # Swift build artifacts
    ]
    files = [
        WORKSPACE_PATH / "requirements.txt",   # Python deps
        WORKSPACE_PATH / "Package.swift",       # SPM manifest
        WORKSPACE_PATH / "Package.resolved",    # SPM lockfile
    ]
    for t in dirs:
        if t.is_dir():
            shutil.rmtree(t, ignore_errors=True)
            print(f"Cleaned stale directory: {t.name}/")
    for t in files:
        if t.is_file():
            t.unlink(missing_ok=True)
            print(f"Cleaned stale file: {t.name}")


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
        "Build the 'Open Cowork' v0.1 app as specified in proposal.md.\n\n"
        "CRITICAL FIRST STEP:\n"
        'Call file_read_tool("proposal.md") to read the full project proposal.\n'
        "Do NOT guess the requirements -- read the actual file.\n\n"
        "MANAGER WORKFLOW:\n"
        "1. Read proposal.md thoroughly\n"
        "2. Break the entire app into small, concrete milestones with numbered tasks\n"
        "3. Delegate ONE small task at a time to a worker\n"
        "4. After each worker: ACKNOWLEDGE -> VERIFY with list_workspace_tool -> "
        "UPDATE PROGRESS -> ASSIGN NEXT TASK\n"
        "5. Always specify: 'Write COMPLETE implementations -- no stubs, no TODOs'\n"
        "6. When a milestone is complete, route to Tester_QA for verification + commit\n"
        "7. Repeat until all milestones are done\n"
        "8. When fully complete: 'PROJECT COMPLETE' -> FINISH"
    )

    if len(sys.argv) > 1:
        TASK_PROMPT = " ".join(sys.argv[1:])

    print("Launching Autonomous Coding Team (LangGraph Supervisor Pattern)\n")
    output = run_autonomous_team(TASK_PROMPT)
    print(f"\n{'-'*70}")
    print("FINAL OUTPUT:")
    print(output)
    print(f"{'-'*70}")
