# Open Cowork — Implementation Checklist

> Living document tracking what has been implemented vs what still needs to be built.
> Based on [`proposal.md`](./proposal.md) roadmap v0.1–v0.5.
> Generated: May 25, 2026.

---

## Legend

| Icon | Meaning |
|:----:|---------|
| ✅ | Fully implemented |
| ⚠️ | Partially implemented (see notes) |
| ❌ | Not started |

---

## 🟢 v0.1 — Foundation (Launch) — Critical

### Core Architecture

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | **Native menubar app with chat panel** | ✅ Done | `StatusItemController` + `MainPanelView` + `ChatView` — fully implemented. Floating NSPanel, brain icon in menubar, resizable with visual effects background. |
| 2 | **macOS Accessibility API control** | ✅ Done | `macOSControlClient` has full AX tree traversal, `clickMouse`, `typeText`, `keyStroke`, `scrollMouse`, `dragMouse`, `launchApp`. Recursive AX element inspection up to depth 4. |
| 3 | **ScreenCaptureKit screenshot capture** | ✅ Done | Uses `SCScreenshotManager` (macOS 14+) with CoreGraphics `CGDisplayCreateImage` fallback. Images resized to max 1600px, compressed as JPEG at 70% quality. |
| 4 | **CGEvent mouse & keyboard simulation** | ✅ Done | Mouse movement, clicks (left/right/double), dragging, scrolling, text typing, key combinations all use `CGEvent` via `CGEventSource`. |
| 5 | **App launching & window focus** | ✅ Done | `launchApp` searches by bundle ID, then `/Applications` and `/System/Applications`. Uses `NSWorkspace.shared.openApplication`. |

### Model & Cost

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 6 | **BYOK: Any OpenAI-compatible API** | ✅ Done | `LLMClient` supports both OpenAI-compatible (`/chat/completions`) and Anthropic (`/messages`) endpoints. `LLMConfig` covers OpenAI, Anthropic, Gemini, OpenRouter, Ollama, LM Studio, Custom. |
| 7 | **Live token & cost display** | ✅ Done | `ChatView` footer shows session cost (4 decimal places) + token counts (in/out). Updated after each API call. |
| 8 | **Cost estimation per provider** | ✅ Done | `LLMClient.calculateCost()` has rate tables for OpenAI, Anthropic, Gemini, OpenRouter, local, and custom endpoints. |
| 9 | **Zero markup — users pay providers directly** | ✅ Done | No billing system, no subscription — purely BYOK pass-through. |

### Safety

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 10 | **Safety mode selector + emergency stop** | ✅ Done | Three safety modes: Full Auto, Approve Before Action, Step Through. Prominent red emergency stop banner in ChatView. Global Cmd+Shift+Esc shortcut. |
| 11 | **Live action log** | ✅ Done | `ChatView` shows step-by-step execution history with timestamp, thought, action description, screenshot preview, and status icon per step. |
| 12 | **Per-app permission allowlist** | ✅ Done | `allowedApps` in `AppStore` (default: Finder, Safari, TextEdit, Terminal, System Settings, Notes, Xcode, Figma). Checked in `AgentStore` against the frontmost app. Edit UI in Settings. |
| 13 | **File undo / rollback** | ✅ Done | `FileRollbackManager` backs up files before writes, supports full session rollback, "Undo File Changes" button in `ChatView`. |

### UX & Install

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 14 | **Onboarding with permission prompts** | ✅ Done | `OnboardingView` checks Accessibility + Screen Recording permissions, shows Enable buttons linking to System Preferences, polls every 1.5s until granted. |
| 15 | **Permissions polling & auto-dismiss** | ✅ Done | `MainPanelView` shows onboarding until both permissions are granted, then switches to main UI. |
| 16 | **`brew install` or signed `.dmg`** | ❌ **Not started** | No Homebrew formula, no DMG packaging script, no code signing configuration. **Blocks shipping.** |
| 17 | **macOS 12 Monterey+ support** | ✅ Done | `Project.swift` sets deployment target to macOS 12.0. Uses `@available(macOS 14.0)` guards for ScreenCaptureKit with CoreGraphics fallback. |
| 18 | **MIT / Apache 2.0 license** | ✅ Done | MIT license created at project root (`LICENSE` file). |

### Gaps in v0.1

| # | Missing Item | Impact | Suggested Fix |
|---|-------------|--------|--------------|
| M1 | ✅ **Done** | Emergency stop banner + global Cmd+Shift+Esc shortcut implemented. See #10. | ✅ Fixed |
| M2 | ✅ **Done** | Safety mode picker (Full Auto / Approve Before Action / Step Through) in Settings. AgentStore loop honors all three modes. | ✅ Fixed |
| M3 | ✅ **Done** | History tab in MainPanelView with session list, expandable step details, re-run, undo files, and delete actions. | ✅ Fixed |
| M4 | ⚠️ **No SQLite storage** | All data stored in `UserDefaults` — not scalable, no querying, no data integrity. Proposal specifies SQLite. | Migrate to SQLite or GRDB.swift for persistent storage of sessions, tasks, skills, settings. |

---

## 🟢 v0.2 — Vision + Safety

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | **Vision fallback for non-AX apps** | ✅ Done | Screenshots captured, compressed, and sent to the LLM as base64 images in both OpenAI and Anthropic formats. |
| 2 | **Per-app allowlist (v0.1 carry-over)** | ✅ Done | See v0.1 #12. |
| 3 | **File undo and rollback (v0.1 carry-over)** | ✅ Done | See v0.1 #13. |
| 4 | **Budget limit / cost cap** | ✅ Done | `budgetLimit` in `AppStore` (default $5.00), checked each iteration in `AgentStore`. `spentThisMonth` tracks running total with reset button. |

### Gaps in v0.2

| # | Missing Item | Impact | Suggested Fix |
|---|-------------|--------|--------------|
| M5 | ❌ **Prompt injection detection** | No warnings when on-screen content appears to contain instructions to the agent. | Add heuristic/LLM-based check after each screenshot capture. |
| M6 | ⚠️ **No explicit pixel-level coordinate analysis** | Relies entirely on LLM vision to interpret coordinates from screenshots. Proposal mentions dedicated vision coordinate analysis. | Add a coordinate extraction utility that identifies UI regions from screenshots and passes them to the LLM. |

---

## 🟠 v0.3 — Automation

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | **Cron-based scheduled tasks** | ✅ Done | `SchedulerView` for CRUD, `SchedulerStore` with 1-min timer aligned to clock minute, `CronMatcher` with full expression parsing (*/steps, ranges, lists, day-of-week). |
| 2 | **Task history and run logs** | ✅ Done | History tab now provides full session browsing with step details, costs, and action buttons (re-run, undo, delete). |
| 3 | **Plugin / skill system v1** | ✅ Done | `SkillsView` with expandable details, `Skill` model with `systemPromptInstructions`, skills injected into `AgentStore.getSystemPrompt()`. Three default skills: Web Search, File Manager, Browser Control. |
| 4 | **Community skill registry** | ❌ Not started | No remote skill registry, no install-from-URL, no skill discovery. |

### Gaps in v0.3

| # | Missing Item | Impact | Suggested Fix |
|---|-------------|--------|--------------|
| M7 | ❌ **Skill creation UI** | Users can't create custom skills through the UI — only toggle built-in ones. | Add a skill editor with name, description, and system prompt fields. |
| M8 | ❌ **Task chaining (completion triggers next)** | No way to chain tasks. Proposal mentions "chain tasks: completion of one task triggers the next." | Add a `dependsOn` field to `ScheduledTask` model. |

---

## 🔵 v0.4 — Reach (Not Started)

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | **Remote WebUI** | ❌ Not started | Local HTTP server + browser UI for remote task dispatch. |
| 2 | **Phone access (QR login)** | ❌ Not started | QR code generation, phone-friendly UI. |
| 3 | **Telegram integration** | ❌ Not started | Telegram bot for remote task dispatch. |
| 4 | **Voice input via local Whisper** | ❌ Not started | Microphone permission is already declared in Info.plist. |

---

## 🟣 v0.5 — Ecosystem (Not Started)

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | **Multi-agent parallel execution** | ❌ Not started | Only one task at a time. `isLoopRunning` guard prevents concurrent runs. |
| 2 | **MCP server compatibility** | ❌ Not started | No Model Context Protocol support. |
| 3 | **Windows / Linux support** | ❌ Not started | macOS-only via AppKit/CGEvent/Accessibility APIs. |
| 4 | **Full provider breadth** | ⚠️ Partial | 7 providers implemented. OpenRouter covers 200+ models but specific provider configs (Bedrock, Azure, etc.) not individually implemented. |

---

## 🚧 Critical Path (Ship-blocking)

These items **must** be completed before the app can be shipped to users:

| Priority | Item | Why it blocks shipping | Effort |
|----------|------|-----------------------|--------|
| 🔴 P0 | ✅ Done | Build succeeds with `xcodebuild`. | — |
| 🔴 P0 | ✅ Done | MIT license created. | — |
| 🔴 P1 | ✅ Done | Emergency stop banner + global Cmd+Shift+Esc. Three safety modes implemented. | — |
| 🔴 P1 | ✅ Done | Safety mode picker with Full Auto / Approve Before Action / Step Through. AgentStore honors all modes. | — |
| 🟡 P2 | **DMG packaging or Homebrew formula** | Required for non-developer installation. | 3–4h |
| 🟡 P2 | ✅ Done | New History tab with session browsing, step details, re-run/undo/delete. | — |
| 🟡 P2 | **SQLite migration** | UserDefaults is not suitable for production data. Will cause data loss or corruption. | 4–6h |

---

## 📊 Progress Summary

| Milestone | Total Items | ✅ Done | ⚠️ Partial | ❌ Missing | Completion |
|-----------|:-----------:|:-------:|:----------:|:----------:|:----------:|
| v0.1 Foundation | 18 | 17 | 0 | 1 | **94%** |
| v0.2 Vision+Safety | 4 | 4 | 0 | 0 | **100%** |
| v0.3 Automation | 4 | 3 | 1 | 0 | **88%** |
| v0.4 Reach | 4 | 0 | 0 | 4 | **0%** |
| v0.5 Ecosystem | 4 | 0 | 1 | 3 | **13%** |
| **Overall** | **34** | **24** | **1** | **9** | **71%** |
