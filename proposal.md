# Open-Source Mac AI Desktop Agent — Product Proposal

> A free, open-source, bring-your-own-key AI agent that physically controls your Mac — moving the mouse, typing on the keyboard, and operating any native app — with no subscription and full transparency over what you spend.

---

## Table of Contents

1. [The Problem](#the-problem)
2. [The Vision](#the-vision)
3. [How It Works](#how-it-works)
4. [Core Features](#core-features)
5. [Competitor Landscape](#competitor-landscape)
6. [Competitive Advantage](#competitive-advantage)
7. [Minimum Requirements for Launch](#minimum-requirements-for-launch)
8. [Technical Architecture](#technical-architecture)
9. [Open-Source Strategy](#open-source-strategy)
10. [Roadmap](#roadmap)

---

## The Problem

Today's AI tools fall into one of two traps:

**Trap 1 — Locked and expensive.** Claude Cowork and OpenAI Operator can genuinely control your Mac, but they're paywalled behind $20–$100/month subscriptions, locked to a single AI provider, and closed-source. You have no visibility into what they do or what they cost per task.

**Trap 2 — Open but hollow.** Open-source agents like OpenClaw (350k+ GitHub stars) and AionUi are free and BYOK, but they don't actually control your desktop. They automate through shell commands, browser APIs, and file operations — they cannot open Figma and drag a layer, click a button in a native macOS app, or interact with anything that doesn't have an API.

**The gap:** No free, open-source tool combines real GUI-level Mac control (actual mouse movement, actual keyboard input, actual screen vision) with a bring-your-own-key model, transparent costs, and a UX that non-developers can use.

That is the gap this project fills.

---

## The Vision

An AI agent that sits in your Mac's menubar and works alongside you — not in a sandboxed VM, not through a messaging bot, but directly on your real desktop.

You describe a task in plain language. The agent sees your screen, reasons about what to do, and executes it: opening apps, clicking buttons, typing text, navigating menus, reading what's on screen, and adapting when things change. You watch everything it does in real time, and you're always in control.

It costs nothing to run the software. You only pay your AI provider for the tokens you use — no markup, no subscription, full transparency.

**Core promise:** If you can do it on your Mac, the agent can do it for you.

---

## How It Works

The agent uses a two-layer approach to control your Mac:

### Layer 1 — macOS Accessibility API (primary)
The Accessibility API lets the agent "see" the semantic structure of any macOS app — buttons, text fields, menus, labels — by their role and label rather than by pixel position. This means:
- It finds the right element even if the window is resized or the UI shifts
- It works reliably across all well-behaved macOS apps
- Actions are precise and fast

### Layer 2 — ScreenCaptureKit + Vision fallback (secondary)
For apps that don't expose an accessibility tree (games, some Electron apps, poorly accessible apps), the agent captures a screenshot using Apple's `ScreenCaptureKit` framework and passes it to the vision-capable AI model. The model identifies elements by what they look like and directs pixel-level cursor movement via `CGEvent`.

This dual-layer approach means the agent can control **any** app on your Mac — not just the well-behaved ones.

### The action loop
1. User gives a task in natural language
2. Agent captures the current screen state
3. AI model reasons about the next action
4. Agent executes: click, type, scroll, open app, run command, etc.
5. Agent captures new screen state and repeats until the task is complete
6. User sees a live log of every action taken

---

## Core Features

### 🖱️ Real Desktop Control
- Move the cursor and click on anything on screen
- Type into any native macOS app — not just browsers or terminals
- Drag and drop, scroll, right-click, and use keyboard shortcuts
- Open, close, resize, and switch between apps
- Read what's currently on screen and act on it

### 🔑 Bring Your Own Key (BYOK)
- **Any OpenAI-compatible API** — configure base URL + API key for any provider
- **AI Providers supported:** Anthropic, OpenAI, Google (Gemini), DeepSeek, Mistral, Cohere, xAI (Grok), Perplexity, Together AI, Groq, Deep Infra, Fireworks AI, Amazon Bedrock, Azure OpenAI, Hugging Face, Nvidia, Cerebras, NovitaAI, and 80+ more through OpenRouter
- **Local / zero-cost:** Ollama, LM Studio, llama.cpp for fully local operation
- **OpenRouter hub:** Unified access to 200+ models across 80+ providers including 302.AI, Abacus, AIHubMix, Alibaba, Amazon Bedrock, Anthropic, Atomic Chat, Azure OpenAI, Bailing, Baseten, Berget.AI, Cerebras, Chutes, Clarifai, CloudFerro Sherlock, Cloudflare AI Gateway, Cohere, Cortecs, D.Run, Deep Infra, DeepSeek, DigitalOcean, Dinference, evroc, FastRouter, Fireworks AI, Firmware, Friendli, FrogBot, GitHub Copilot, GitLab Duo, Google, Google Vertex AI, Groq, Helicone, HPC-AI, Hugging Face, iFlow, Inception, Inference, IO.NET, Jiekou.AI, Kilo Gateway, Kimi For Coding, KUAE Cloud, Llama, LMStudio, llama.cpp, LucidQuery AI, Meganova, MiniMax, Mistral, Mixlayer, Moark, ModelScope, Moonshot AI, Morph, NanoGPT, Nebius Token Factory, Nova, NovitaAI, Nvidia, Ollama, OpenAI, OpenRouter, OVHcloud, Perplexity, Poe, Privatemode AI, QiHang, Qiniu, Regolo AI, Requesty, SAP AI Core, Scaleway, SiliconFlow, STACKIT, StepFun, submodel, Synthetic, Tencent, The Grid AI, Together AI, Upstage, v0, Venice AI, Vercel AI Gateway, Vertex, Vivgrid, Vultr, Wafer, Weights & Biases, xAI (Grok), Xiaomi, Z.AI, ZenMux, Zhipu AI, and any custom OpenAI-compatible endpoint
- The app is a zero-margin orchestration layer — every dollar goes to your provider
- Switch models mid-task, or use different models for different task types

### 💰 Transparent Cost Tracking
- See tokens used and estimated cost for every task in real time
- Per-session and per-task cost history
- Budget limits: pause or stop the agent if a cost threshold is hit
- No black-box spending, no subscription mystery

### 🛡️ Safety First
- **Four control modes:** Full auto, approve-before-action, step-through (manual confirm every step), and emergency stop
- **Live action log:** Every click, keystroke, and screenshot shown in real time with timestamps
- **Per-app allowlist:** Define exactly which apps the agent is permitted to touch
- **Undo and rollback:** File operations are reversible; Git-based version history for text changes
- **Prompt injection detection:** Warns when content on screen appears to contain instructions to the agent

### ⏰ Scheduling and Automation
- Cron-based scheduled tasks — run automations daily, weekly, or on custom schedules
- 24/7 unattended operation for repetitive workflows
- Task history and run logs for every scheduled job
- Chain tasks: completion of one task triggers the next

### 📱 Remote Access
- Local WebUI accessible from any browser on your network
- QR code or password login
- Send tasks from your phone and watch them execute on your Mac
- Telegram integration for on-the-go task dispatch

### 🎙️ Voice Input
- Trigger tasks hands-free using a keyboard shortcut and speaking naturally
- Local Whisper model for privacy — audio never leaves your machine
- Under 500ms recognition latency on Apple Silicon

### 🧩 Plugin / Skill System
- Community-extensible actions defined in simple markdown + code files
- Skills registry for installing verified community skills
- Built-in skills: web search, file management, document generation, browser control, image generation
- Create custom skills for your own workflows

### 📋 Multi-Task Parallel Execution
- Run multiple agent tasks simultaneously with independent context
- Visual task queue showing status of each running job
- Tasks don't interfere with each other

### 🔒 Privacy by Default
- All data stored locally in a SQLite database
- Nothing uploaded to any server except AI model API calls
- Opt-in crash reporting only
- No telemetry, no usage tracking, no analytics

---

## Competitor Landscape

### Closed-Source / Paid

#### Claude Cowork (Anthropic)
- **What it does:** Full Mac desktop control — real mouse, keyboard, app navigation
- **Price:** Included with Claude Pro ($20/mo) or Max ($100/mo)
- **Similarity to our product:** 95% in capability, 0% in philosophy
- **What it lacks:** Open source, BYOK, cost transparency, Windows/Linux support, cron scheduling, community extensibility
- **Our advantage:** We're the free, open, model-agnostic version of exactly this

#### OpenAI Operator / Codex
- **What it does:** Browser-first agent (Operator) and Mac desktop control in a sandboxed virtual workspace (Codex)
- **Price:** Included with paid ChatGPT/Codex subscriptions
- **What it lacks:** Open source, BYOK, native Mac accessibility integration, transparent costs
- **Note:** Codex's virtual workspace doesn't block your cursor but also doesn't operate your real apps — it's isolated

#### Perplexity Computer
- **What it does:** Digital worker spanning research, web, and desktop tasks across 19 models
- **Price:** Subscription-based
- **What it lacks:** Open source, BYOK, native Mac integration

---

### Open-Source with Real GUI Control

#### Agent! (macOS26/Agent) — **Similarity: 90%**
- **What it is:** Native Swift macOS app, Accessibility API control via AXorcist, 18 LLM providers, fully BYOK
- **Strengths:** Closest technical match to our vision — real AX control, 18 providers, voice, iMessage remote, MCP support, Time Machine rollback
- **What it lacks:**
  - Mac only (no Windows/Linux)
  - Developer and coding IDE focus — not a general-purpose desktop agent
  - No cron/scheduled tasks
  - No remote WebUI
  - No transparent cost tracking
  - No screen-vision fallback for apps without AX tree
  - No consumer-grade onboarding UX

#### Fazm — **Similarity: 82%**
- **What it is:** Native macOS app, Accessibility API + keyboard/mouse simulation, local Whisper voice, file knowledge graph, MIT license
- **Strengths:** Deep macOS integration, local-first privacy, DOM-level browser control, scheduled tasks
- **What it lacks:**
  - $9.99/month for the bundled app (undercuts its open-source story)
  - Limited BYOK model flexibility
  - Mac only
  - No multi-agent orchestration
  - No remote access
  - No transparent cost tracking

#### Open Computer Use (coasty-ai) — **Similarity: 78%**
- **What it is:** Electron + FastAPI, multi-agent planner (browser/terminal/desktop agents), runs in a Docker Linux VM, 82% OSWorld benchmark score
- **Strengths:** Vision-based computer control, multi-agent planning, excellent benchmark performance, streaming action view
- **What it lacks:**
  - Controls a containerized Linux VM, **not your actual Mac** — your real apps are untouched
  - Complex Docker setup — not accessible to non-developers
  - No macOS Accessibility API
  - No voice input
  - No scheduled tasks
  - Billing/Stripe hooks in the open-source repo suggest a commercial pivot

#### UI-TARS Desktop (ByteDance) — **Similarity: 72%**
- **What it is:** Cross-platform Electron app, vision-language model for GUI control, screenshot-based recognition, Apache 2 license
- **Strengths:** Real mouse/keyboard control across platforms, strong vision-based grounding, remote computer and browser operators
- **What it lacks:**
  - Pushes ByteDance's own UI-TARS model — true BYOK is not the design intent
  - No macOS Accessibility API integration
  - No voice input
  - No cron/scheduling
  - No remote WebUI
  - Trust concerns around ByteDance ownership for Western users

#### Agent-S (Simular AI) — **Similarity: 65%**
- **What it is:** Research framework, SOTA OSWorld scores (first to surpass human-level performance at 72.6%), BYOK, Apache 2 license
- **Strengths:** Best benchmark performance of any open-source system, clean BYOK design, strong academic foundation
- **What it lacks:**
  - CLI only — zero consumer-facing interface
  - Requires running a separate grounding model server
  - No scheduled tasks, voice, remote access, or any UX layer
  - Pure research tool — not usable by non-developers

---

### Open-Source Without Real GUI Control

#### AionUi (iOfficeAI) — **Similarity: 45%**
- **What it is:** Electron GUI shell wrapping Claude Code, Codex, Gemini CLI, OpenClaw, and 12+ other CLI agents. 22.3k GitHub stars, 95 releases, active development.
- **Strengths:** Polished UX, cron scheduling, remote WebUI + phone access, 20+ model providers, document generation (PPT/Word/Excel), multi-task parallel execution
- **What it lacks:** Any real desktop control — it's a front-end for CLI agents. Cannot move your cursor, click native app buttons, or see your screen. A UI shell, not a computer-use agent.
- **Opportunity:** Could integrate with our project — AionUi as the orchestration UI, our agent as the motor cortex

#### OpenClaw (formerly Clawdbot) — **Similarity: 22%**
- **What it is:** The most-starred open-source project in GitHub history (350k+ stars). Local agent runtime, 100+ community skills, messaging-app interface (WhatsApp, Telegram, Discord, etc.), MIT license.
- **Strengths:** Massive community, BYOK, excellent skills ecosystem, proactive intelligence
- **What it lacks:** Any real desktop control. Operates through shell, file system, browser APIs. Cannot interact with native Mac apps. Also hit by a major supply chain attack (ClawHavoc, 2026) exposing security risks.

#### Bytebot — **Similarity: 40%**
- **What it is:** Self-hosted AI desktop agent running in a containerized Linux desktop environment. BYOK, natural language task input, Docker-based.
- **Strengths:** BYOK, full virtual desktop with any app, natural language interface
- **What it lacks:** Controls a Linux VM, not your Mac. Docker dependency. No native macOS integration. No voice, scheduling, or consumer UX.

#### NeuralAgent — **Similarity: 35%**
- **What it is:** Open-source Electron + FastAPI app using PyAutoGUI for mouse/keyboard control. Multi-model (Claude, GPT, Gemini, Ollama), modular architecture.
- **Strengths:** Real mouse/keyboard control via PyAutoGUI, multi-model support, modular agent architecture
- **What it lacks:** Limited error recovery (requires manual restart when stuck), no macOS Accessibility API (pixel-only), Mac background automation not available, developer-facing UX, no scheduling or remote access.

---

## Competitive Advantage

Our product is the only tool that combines all of the following simultaneously:

| Feature | Our App | Agent! | Fazm | Open Computer Use | AionUi | OpenClaw |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Real mouse & keyboard on your Mac | ✅ | ✅ | ✅ | ❌ (VM) | ❌ | ❌ |
| macOS Accessibility API | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Vision fallback (ScreenCaptureKit) | ✅ | ❌ | ❌ | ✅ (VM) | ❌ | ❌ |
| True BYOK (any provider) | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| Live cost tracking | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Consumer-grade UX + one-click install | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ |
| Cron / scheduled tasks | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Remote access (phone/WebUI) | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| Completely free (no paid tier) | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| Cross-platform (future) | 🔜 | ❌ | ❌ | ✅ | ✅ | ✅ |

The critical combination no one else has: **real Mac GUI control + BYOK + polished UX + fully free**.

---

## Minimum Requirements for Launch

These are the non-negotiables. The app is not ready to ship without all of these.

### 🔴 Critical — Must ship at launch

**Computer control**
- Real mouse movement and click via `CGEvent` / macOS Accessibility API
- Keyboard input into any native Mac app
- ScreenCaptureKit screenshot capture for vision fallback
- App launching, window focus, and switching

**Model & cost**
- BYOK: Any OpenAI-compatible API — Anthropic, OpenAI, Google (Gemini), DeepSeek, Mistral, Cohere, xAI (Grok), Perplexity, Together AI, Groq, Deep Infra, Fireworks AI, Ollama, LM Studio, and 80+ providers via OpenRouter — at minimum
- Live token and estimated cost display per task
- Zero markup — users pay providers directly

**Safety**
- Pause / approve-before-action / emergency stop modes
- Real-time action log (every click, keystroke, screenshot)
- Per-app permission allowlist

**UX & install**
- `brew install` or signed `.dmg` — zero terminal configuration
- Native menubar app with floating chat panel
- Works on macOS 12 Monterey or later

**Open-source hygiene**
- MIT or Apache 2.0 license
- `CONTRIBUTING.md` + dev environment setup in under 5 minutes
- GitHub Discussions or Discord live at launch

### 🟡 High priority — First few releases

- Cron-based scheduled task runner
- File undo and rollback (Git-based for text, Trash integration for files)
- Local Ollama / LM Studio support
- Plugin / skill system with community registry
- Budget limits (pause agent if cost threshold exceeded)
- All data stored locally — no telemetry by default

### 🟢 Nice to have — Later releases

- Voice input via local Whisper
- Remote WebUI + phone access
- Telegram / Slack integration for remote task dispatch
- Multi-agent parallel execution
- Windows and Linux support
- MCP server compatibility

---

## Technical Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User Interface                        │
│         Native macOS menubar app (Swift / SwiftUI)       │
│    Floating chat panel · Task queue · Action log         │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│                   Agent Orchestrator                     │
│   Task planner · Multi-step reasoning · Memory store     │
│   Cost tracker · Safety checks · Approval gating         │
└──────────────┬──────────────────────────┬───────────────┘
               │                          │
┌──────────────▼──────────┐  ┌────────────▼──────────────┐
│    Control Layer         │  │      AI Model Layer        │
│                          │  │                            │
│  Primary:                │  │  Anthropic (Claude)        │
│  macOS Accessibility API │  │  OpenAI (GPT)              │
│  AXorcist / AXUIElement  │  │  Google (Gemini)           │
│                          │  │  DeepSeek / Mistral        │
│  Fallback:               │  │  Ollama (local)            │
│  ScreenCaptureKit        │  │  LM Studio (local)         │
│  CGEvent (mouse/kb)      │  │  OpenRouter (hub)          │
│                          │  │                            │
│  Supporting:             │  │  Vision model for          │
│  Shell execution         │  │  screenshot analysis       │
│  File system ops         │  └────────────────────────────┘
│  Browser control         │
└──────────────────────────┘
```

**Language:** Swift 6 for the native macOS app and control layer. Python or TypeScript for the agent orchestrator and skill runner (TBD based on community preference).

**Storage:** SQLite for all local data (task history, cost logs, memory, settings).

**Model communication:** Standard Anthropic, OpenAI-compatible, and Ollama APIs.

**Safety boundary:** All file operations are staged before execution. A rollback manifest is written before destructive actions.

---

## Open-Source Strategy

### License
Apache 2.0. Permissive enough to encourage commercial products building on top, with patent protections.

### Community flywheel
1. Launch with a complete, working v0.1 — not a demo
2. Discord live on launch day
3. Pre-written "good first issue" tickets covering skill development, UI polish, and provider integrations
4. Clear skill creation docs so contributors can extend the agent without touching core code
5. Public roadmap where the community votes on priorities

### What we won't do
- No paid tier, no "pro" version
- No selling usage data
- No telemetry without explicit opt-in
- No locking the agent to any single AI provider
- No VC funding that could compromise the open-source commitment

### What makes contributors stay
- Skills are independent modules — easy to write, easy to merge, easy to maintain
- Core agent loop is well-documented and stable so contributors aren't fighting a moving target
- Security is taken seriously from day one — no repeat of the OpenClaw ClawHavoc incident

---

## Roadmap

### v0.1 — Foundation (launch)
- Native menubar app with chat panel
- macOS Accessibility API control
- BYOK: Any OpenAI-compatible API (Anthropic, OpenAI, Google, DeepSeek, Mistral, Cohere, xAI, Together AI, Groq, Fireworks AI, Ollama, LM Studio, and 80+ more via OpenRouter)
- Live action log
- Approve-before-action safety mode
- Live cost display
- `brew install` + signed `.dmg`
- MIT license, CONTRIBUTING.md, Discord

### v0.2 — Vision + Safety
- ScreenCaptureKit screenshot capture
- Vision fallback for non-AX apps
- Per-app permission allowlist
- File undo and rollback
- Budget limit / cost cap

### v0.3 — Automation
- Cron-based scheduled tasks
- Task history and run logs
- Plugin / skill system v1
- Community skill registry

### v0.4 — Reach
- Remote WebUI
- Phone access (QR login)
- Telegram integration
- Voice input via local Whisper

### v0.5 — Ecosystem
- Multi-agent parallel task execution
- MCP server compatibility
- Full provider support (Gemini, DeepSeek, Mistral, OpenRouter)
- Windows and Linux support (alpha)

---

## Summary

This project is the answer to a simple question that no one has answered yet: *why can't the open-source world have what Claude Cowork has?*

Real Mac desktop control. Any AI model. No subscription. Full transparency. Consumer-grade UX. Completely free and open.

The tools exist. The APIs are public. The community is ready — 350,000 people starred OpenClaw in 60 days looking for exactly this kind of agent. The only thing missing is a project that combines real computer control with the open, free, BYOK philosophy those people actually want.

That's this project.

---

*Generated May 2026. Competitor information accurate as of research date.*
