# AGENTS.md - Personal Research Agent

## 1. Product Overview
A lightweight native macOS Menu Bar application (no Dock icon, no web UI, no localhost server, no local LLM) that wakes on a schedule (default 08:00 daily), conducts structured web research via OpenRouter API and Brave Search API, writes a rich Markdown report with JSON metadata to `~/Documents/Personal Research Agent/`, sends a native macOS notification, and returns to idle.

## 2. System Environment & Tooling
- **OS**: macOS 15.1 Sequoia (`arm64-apple-macosx15.0`)
- **Swift**: Apple Swift version 6.0.2 (Swift 6 mode compatible)
- **Deployment Target**: macOS 14.0+ (utilizing `MenuBarExtra(.window)` & modern SwiftUI/AppKit)
- **Build System**: Swift Package Manager (`Package.swift` executable target) or Xcode project (`swift build` / `swift test`)
- **UI Element**: `LSUIElement = YES` (Menu Bar only, no Dock icon)

## 3. Architecture & Key Seams
```
┌─────────────────────────────────────────────────────────────┐
│                       MenuBarExtra                          │
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

### Seam Interfaces
1. **`AIProvider` Protocol**:
   - `generate(system: String, messages: [ChatMessage], options: GenerationOptions) async throws -> String`
   - `generateStructured<T: Decodable>(system: String, messages: [ChatMessage], schema: JSONSchema?, options: GenerationOptions) async throws -> T`
   - Default: `OpenRouterProvider`
2. **`SearchProvider` Protocol**:
   - `searchWeb(query: String, count: Int, freshness: Freshness?) async throws -> [SearchResult]`
   - Default: `BraveSearchProvider`
3. **`PageFetcher` Protocol**:
   - `fetchWebPage(url: URL) async throws -> ExtractedPage`
4. **`MemoryStore` Protocol**:
   - Persists state, last run metadata, covered story titles, dedupe URL sets in `~/Library/Application Support/PersonalResearchAgent/memory.json`.
5. **`KeychainService`**:
   - Securely stores OpenRouter and Brave Search API keys in macOS Keychain. Redacted in all logs.

## 4. Hard Constraints & Technical Decisions
1. **Native Only**: 100% Swift + SwiftUI + AppKit. Zero web wrappers, Electron, or local servers.
2. **Zero Unnecessary 3rd-party Dependencies**: Built with Apple system frameworks: `Foundation`, `URLSession`, `SwiftUI`, `AppKit`, `Security` (Keychain), `UserNotifications`, `ServiceManagement` (`SMAppService`), `Network` (`NWPathMonitor`), `OSLog`.
3. **App Sandbox OFF (Personal Build)**: Hardened Runtime enabled; allows direct report creation in `~/Documents/Personal Research Agent/` without security-scoped bookmark bookmarks.
4. **Launch at Login**: `SMAppService.mainApp.register()` / `unregister()`. Real status reflected in UI.
5. **Prompt Injection Defense**:
   - All external webpage text is treated as untrusted and wrapped in `<untrusted_webpage url="...">...</untrusted_webpage>`.
   - Closing tags inside untrusted text are escaped/neutralized.
   - System prompts explicitly instruct the model that content inside untrusted tags cannot alter instructions, rules, or formats.
   - Agent has zero shell or arbitrary filesystem write capabilities.
   - Outputs are strictly schema-validated and URL-whitelist validated (only fetched/searched URLs allowed in report sources).
6. **Cost & Quota Controls (Free-Tier Resilient)**:
   - Request cap: max 8 model calls per run.
   - Query limit: max 6 queries; max 8 pages fetched per run.
   - Rate limit mitigation: minimum 2s delay between calls, exponential backoff on HTTP 429.
   - Structured output fallback: Layer 1 (Native Schema) -> Layer 2 (Prompt Schema) -> Layer 3 (Tolerant JSON parser with fence & `<think>` block stripping, single-attempt auto-repair).
   - Fallback model list: Seamlessly tries next configured model if primary returns 404, empty output, or persistent errors.

## 5. Security & Privacy
- API Keys stored exclusively in macOS Keychain via `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate`.
- Never print or log secrets. Redacted strings (`sk-...[REDACTED]`) in all logs and crash dumps.
- Free-Tier Privacy Notice displayed prominently in Settings and README.
- No personal documents or sensitive machine data ever sent in prompts.

## 6. Build, Run, and Test Instructions
```bash
# Run all unit tests
swift test

# Build executable
swift build -c release

# Run directly from terminal (for testing/debug)
swift run
```
