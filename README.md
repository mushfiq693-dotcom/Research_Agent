# Personal Research Agent (Native macOS)

An autonomous, lightweight native macOS Menu Bar application that wakes on a schedule (default 08:00 AM daily), conducts structured web research via OpenRouter AI models and the Brave Search API, compiles rich Markdown reports with JSON metadata to `~/Documents/Personal Research Agent/`, delivers native macOS notifications, and returns to idle.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      MenuBarExtra UI                        │
│        (PopoverView, SettingsView, Status Indicators)       │
└──────────────────────────────┬──────────────────────────────┘
                               │ Observable AppState
┌──────────────────────────────▼──────────────────────────────┐
│                      RunCoordinator                         │
│   (Orchestrates Trigger -> Loop -> Write -> Notify -> Idle) │
└──────┬───────────────────────┬───────────────────────┬──────┘
       │                       │                       │
┌──────▼──────┐         ┌──────▼──────┐         ┌──────▼──────┐
│  Scheduler  │         │ResearchAgent│         │Notifications│
│(Timer/Wake) │         │ (Agent Loop)│         │(UNUserNotif)│
└─────────────┘         └──────┬──────┘         └─────────────┘
                               │
            ┌──────────────────┴──────────────────┐
            │                                     │
     ┌──────▼───────┐                      ┌──────▼───────┐
     │  AIProvider  │                      │SearchProvider│
     │ (OpenRouter) │                      │ (BraveSearch)│
     └──────┬───────┘                      └──────┬───────┘
            │                                     │
     ┌──────▼───────┐                      ┌──────▼───────┐
     │ 3-Layer JSON │                      │ PageFetcher  │
     │Model Catalog │                      │HTML Extractor│
     └──────────────┘                      └──────────────┘
```

---

## Key Features

1. **100% Native macOS Application**:
   - Built entirely in Swift + SwiftUI with `MenuBarExtra(.window)` styling.
   - Runs strictly in the macOS Menu Bar (`LSUIElement = true` / `NSApp.setActivationPolicy(.accessory)` with zero Dock clutter).
   - Zero third-party web frameworks, Electron, local servers, or local LLMs required.
2. **Autonomous Daily Scheduling & Wake Observer**:
   - Configurable schedule (Daily at 08:00 AM or Weekly on custom weekdays).
   - Observes `NSWorkspace.didWakeNotification`. If the Mac was asleep during a scheduled run, the agent automatically executes a single catch-up run upon wake.
3. **Security & Prompt-Injection Defense**:
   - **Keychain Storage**: API keys are securely stored and retrieved exclusively through the macOS Keychain (`Security` framework). Keys are automatically redacted in logs (`sk-or...[REDACTED]`).
   - **Prompt Injection Neutralization**: All external web content is enclosed within `<untrusted_webpage url="...">` wrappers. Any internal closing tag sequences (e.g. `</untrusted_webpage>`, `</system>`) are neutralized to prevent breakout.
   - **Code-Level URL Whitelist**: Every link in the generated Markdown report is validated against the set of URLs actually searched/fetched. Fabricated URLs are discarded.
4. **Free-Tier Resilient AI Engine**:
   - **3-Layer Tolerant Parsing**: Native Schema $\rightarrow$ Prompt Schema $\rightarrow$ Tolerant Parser (stripping ````json fences and `<think>...</think>` reasoning tags, with automated single-attempt repair).
   - **Fallback Model Traversal**: Automatically tries secondary free models (e.g. `qwen/qwen3.8-27b:free`, `nex-agi/nex-n2.5-pro:free`) if the primary model returns 404, 5xx, or empty outputs.
   - **Rate Limit Spacing**: Enforces minimum delay between calls and handles HTTP 429 backoff gracefully.
5. **Interactive macOS Notifications**:
   - Native notifications delivered via `UNUserNotificationCenter` with an interactive `Open Report` action that opens the report directly in Finder.
6. **Launch at Login**:
   - Integrated with modern `SMAppService.mainApp` API reflecting real system status.

---

## Required API Keys

Before running research, obtain the following two free-tier API keys:

1. **OpenRouter API Key**:
   - Sign up at [openrouter.ai](https://openrouter.ai).
   - Generate an API key at [openrouter.ai/keys](https://openrouter.ai/keys).
   - Free accounts receive 50 free requests/day across all `:free` models (increases to 1,000/day if account has $\ge \$10$ lifetime credits).
2. **Brave Search API Key**:
   - Sign up at [brave.com/search/api](https://brave.com/search/api/).
   - Generates $5/month in free credits (~1,000 search queries).

---

## Free-Tier Cloud Privacy Notice

> [!NOTE]
> **Privacy Notice**: This application communicates with cloud AI models through the OpenRouter API. Free-tier models are served by various cloud inference providers that may log prompts and completions for operational evaluation.
> 
> **Safeguards Built into the Agent**:
> - **Zero Local Files or Personal Data**: The agent never reads, sends, or logs personal files, documents, or secrets in prompts.
> - **Strict Data Scope**: Prompts contain *only* the user's research topic and sanitized public web page extracts.
> - **Local Credentials**: API keys live exclusively in your local macOS Keychain.

---

## App Sandbox & File Storage Policy

This personal build runs with **App Sandbox OFF** (Hardened Runtime enabled). This design allows the application to directly create structured folders and write reports in `~/Documents/Personal Research Agent/` without requiring security-scoped bookmark prompts.

### Output Folder Structure
```
~/Documents/Personal Research Agent/
└── YYYY/
    └── MM/
        ├── YYYY-MM-DD-<topic-slug>.md     # Sourced Markdown Intelligence Report
        └── YYYY-MM-DD-<topic-slug>.json   # Sibling Execution Metadata
```

---

## Build, Run, and Test Instructions

### 1. Run All Automated Test Suites
```bash
# Runs Settings, Core Services, Agent Loop, Scheduler, and Acceptance Test Suites
swift run TestRunner
```

### 2. Build Debug Executable
```bash
swift build
```

### 3. Run Directly from Terminal
```bash
swift run PersonalResearchAgent
```

### 4. Build Release Binary
```bash
swift build -c release
```
The optimized release executable is generated at:
`.build/release/PersonalResearchAgent`

---

## Quick Start & Usage

1. Launch `PersonalResearchAgent`. A sparkling icon appears in the macOS Menu Bar.
2. Click the Menu Bar icon $\rightarrow$ **Settings...**.
3. Under the **AI & Search** tab, enter your OpenRouter Key and Brave Search Key, then click **Save** and **Test**.
4. Under the **General** tab:
   - Select your preferred Topic (e.g. *Latest AI news*, *AI Agents*, *Cybersecurity*, or *Custom*).
   - Set your preferred Schedule Time (e.g. `08:00 AM`).
   - Toggle **Launch at Login** if you want the agent to start automatically with macOS.
5. Click **Research Now** in the Popover to run an instant research cycle or let the agent run automatically on schedule!
