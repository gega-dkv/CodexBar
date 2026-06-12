# CodexBar for Windows — migration design

Date: 2026-06-13
Branch: `windows-migration`
Status: approved (design); implementation plan to follow

## Goal

Ship CodexBar on Windows: a system-tray app whose flyout matches the macOS popover (provider
tab strip, session/weekly usage bars with reset times and pace, extra usage, cost summary,
account actions), backed by the same provider engine as the macOS app and CLI.

## Decision

**Port the Swift engine; build a thin native shell in C#.**

- The provider engine (`CodexBarCore`, ~93K LOC) and the CLI (`CodexBarCLI`) are ported to
  Windows. They already build on Linux in CI (Swift 6.2.1, x64 + ARM, static stdlib), with a
  `.notSupportedOnThisPlatform` degradation model that Windows extends.
- The user-facing shell is new code: C# / .NET 9 / WinUI 3, living in this repo under
  `Windows/`.
- The seam between them is the existing `codexbar serve` local HTTP JSON API. No FFI.

Rejected alternatives:
- **Full C#/.NET rewrite** — re-implements ~93K lines of provider logic and parsers, breaks
  the fork's upstream cherry-pick strategy (`docs/UPSTREAM_STRATEGY.md`) permanently.
- **Tauri/Electron shell** — pixel-perfect flyout via CSS, but adds a Rust+web stack, less
  native tray behavior, larger footprint (Electron). WinUI 3 with Mica/Acrylic gets close
  enough to the macOS look while staying native.
- **Pure-Swift Windows UI** — no production-grade Swift UI toolkit exists on Windows.

## Architecture

Two processes:

```
CodexBar.Windows (C#, WinUI 3)               CodexBarCLI (Swift)
┌─────────────────────────────┐   spawn /    ┌──────────────────────────┐
│ tray icon (percent render)  │  supervise   │ codexbar serve --port N  │
│ flyout window (Acrylic)     │ ───────────► │  GET /health             │
│ settings window             │              │  GET /usage[?provider=]  │
│ serve supervisor + poller   │ ◄─────────── │  GET /cost[?provider=]   │
└─────────────────────────────┘  JSON/HTTP   └──────────────────────────┘
              │                                          │
              └────────── %USERPROFILE%\.codexbar\config.json ──────────┘
```

- The shell picks a free localhost port, launches `codexbar serve --port <N>
  --refresh-interval <ttl>`, and polls `/usage` and `/cost` on the configured cadence.
- Both processes share `~/.codexbar/config.json`: the shell writes settings changes; the
  engine reads them (same contract as the macOS app + CLI today).
- The JSON payload schema is defined by `Sources/CodexBarCLI/CLIPayloads.swift`
  (`ProviderPayload`: usage, credits, status, error, account identity per provider). C# DTOs
  mirror it; contract tests pin both sides to shared fixture files.

## Component 1: engine port (Swift)

- **Platform gates.** Add `#if os(Windows)` beside existing `os(Linux)` gates; unsupported
  strategies throw `.notSupportedOnThisPlatform` (pattern in
  `TestsLinux/PlatformGatingTests.swift`).
- **Works day 1** (no new platform code): OAuth credential files
  (`~/.claude/.credentials.json`, Codex auth — both exist on Windows because those CLIs run
  there), API-key strategies, provider status polling, local cost-log scans
  (`~/.claude/projects`). Paths go through `FileManager`/tilde expansion, which
  swift-corelibs-foundation maps to `%USERPROFILE%` / `%LOCALAPPDATA%` on Windows; audit the
  ~8 files using `cachesDirectory`-style lookups during the port.
- **Stubbed at first, later phases:**
  - Browser cookie import — SweetCookieKit is macOS-only; make it a conditional (macOS-only)
    dependency with a Windows stub. Later: Firefox on Windows is plain SQLite (feasible);
    Chrome uses app-bound encryption since Chrome 127 (likely never).
  - Keychain — stub; later map the cookie/credential caches to Windows Credential Manager
    (DPAPI).
  - CLI PTY probes (`TTYCommandRunner`) — stub; later port to ConPTY.
  - WebKit-based scraping (`OpenAIDashboardFetcher`) — stays macOS-only.
- **Dependencies.** swift-crypto supports Windows (vendors BoringSSL); swift-log, Commander,
  swift-syntax macros are portable. SweetCookieKit is the only one needing a conditional.
- **CI.** Add a `windows-2025` job mirroring the Linux job: install Swift 6.2.x, build
  `CodexBarCLI`, run the platform-agnostic test suite (`TestsLinux` gains Windows
  expectations; rename it to `TestsPortable` as part of that change).

## Component 2: Windows shell (C#)

- **Stack:** .NET 9, WinUI 3 (Windows App SDK), H.NotifyIcon for the tray, Velopack for
  updates. Solution at `Windows/CodexBar.Windows.sln`.
- **Tray icon:** dynamically rendered (provider glyph + usage percent state), regenerated on
  each refresh — equivalent of the macOS status item icon.
- **Flyout:** borderless window anchored above the tray, Mica/Acrylic backdrop, dismiss on
  focus loss. Layout mirrors the macOS popover: provider tab strip with mini usage bars;
  selected provider's sections (header with plan + freshness, session bar, weekly bar with
  pace line, model-specific bars, extra usage, cost today/30-days); footer actions
  (Add Account…, Usage Dashboard, Status Page, Settings…, About, Quit).
- **Settings v1 (minimal):** provider enable/disable, refresh interval, per-provider usage
  source picker (where the descriptor allows), launch at login (StartupTask / Run key).
  Everything writes to `config.json`.
- **Identity siloing:** the shell renders identity (email/org/plan) only from the provider's
  own payload — same hard rule as CLAUDE.md.
- **Resilience:** serve process supervised with restart + backoff; flyout shows last good
  data with "updated X ago" staleness; per-provider errors render inline from the payload's
  `error` field.

## Testing

- Engine: existing parser/strategy tests run on Windows CI; platform-gating tests gain
  Windows expectations.
- Shell: xUnit on view models (payload → view state), JSON contract tests deserializing
  shared fixtures exported from the Swift test fixtures; no UI-automation suite in v1.

## Phases

0. **Toolchain spike (go/no-go):** install the Swift 6.2 Windows toolchain on this machine,
   attempt `swift build --product CodexBarCLI`, catalogue every failure. If the toolchain
   proves unworkable, revisit the rewrite decision with the failure list in hand.
1. **Engine on Windows:** gates + path audit + SweetCookieKit conditional; `codexbar usage`
   returns real data for Claude (OAuth file) and Codex on Windows; Windows CI green.
2. **Shell MVP:** tray icon + flyout with screenshot parity for Codex, Claude, Cursor,
   Droid, Gemini, Copilot; serve supervision and polling.
3. **Product polish:** settings window, launch at login, Velopack installer + updates,
   winget manifest.
4. **Strategy depth:** ConPTY port for CLI probes, Credential Manager-backed caches,
   Firefox cookie import.

## Risks

- **Swift-on-Windows toolchain friction** (linking, macro plugins, Foundation gaps) — the
  Phase 0 spike exists precisely to surface this before any commitment.
- **Serve payload drift** — contract tests on shared fixtures; treat `CLIPayloads.swift`
  changes as API changes.
- **Provider coverage gap at launch** — cookie-based providers won't work on Windows v1;
  the flyout must communicate "not supported on Windows yet" per provider rather than
  showing errors.
