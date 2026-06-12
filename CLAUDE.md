# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

CodexBar is a Swift 6 macOS 14+ menu bar app (plus a cross-platform CLI) that surfaces usage/quota/credit/cost
limits for 40+ AI coding providers. There is no Xcode project — it is a pure SwiftPM package.

## Commands

- Build: `swift build` (debug) or `swift build -c release`. Standalone CLI: `swift build -c release --product CodexBarCLI` → `.build/release/CodexBarCLI`.
- Test (full suite): `make test` / `swift test`.
- Single test: `swift test --filter ClaudeStatusProbeTests` (type) or `swift test --filter ClaudeStatusProbeTests/test_caseName` (method). Some suites have dedicated targets: `make test-tty` (TTYIntegrationTests), `make test-live` (LiveAccountTests, gated by `LIVE_TEST=1`).
- Lint/format: `make check` (runs `swiftformat --lint` + `swiftlint --strict`) and `make format`. **Run `make check` after any code change and fix all issues before handoff.** Tools are pinned and auto-installed into `.build/lint-tools` by `Scripts/lint.sh`.
- Dev loop (UI/runtime validation, macOS only): `./Scripts/compile_and_run.sh` — kills old instances, builds, tests, packages, relaunches `CodexBar.app`. Use this *only* when bundle-level behavior must be verified; prefer focused tests otherwise.

`make check` also verifies `Sources/CodexBarCore/Generated/CodexParserHash.generated.swift`. If you edit anything under `Sources/CodexBarCore/Vendored/CostUsage/`, regenerate it with `Scripts/regenerate-codex-parser-hash.sh` or the check will fail.

## Targets (Package.swift)

- `CodexBarCore` — platform-agnostic fetch + parse + provider descriptors/strategies + shared host APIs. The bulk of the logic. Also builds on Linux.
- `CodexBar` (macOS only) — AppKit/SwiftUI app: state stores, status item, menus, icon rendering, settings, login runners.
- `CodexBarCLI` — `codexbar` CLI (usage/cost/config/diagnose/serve); builds on macOS + Linux.
- `CodexBarWidget`, `CodexBarClaudeWatchdog`, `CodexBarClaudeWebProbe` (macOS only) — WidgetKit extension and Claude helper processes.
- `CodexBarMacros` / `CodexBarMacroSupport` — SwiftSyntax macros (`@ProviderDescriptorRegistration`, etc.) used for provider registration.

## Architecture

**Data flow:** background refresh → `UsageFetcher` / provider probes (in `CodexBarCore`) → `UsageStore` → menu / icon / widgets. Settings toggles feed `SettingsStore`, which drives refresh cadence and feature flags. See `docs/architecture.md` and `docs/refresh-loop.md`.

**Everything is descriptor-driven — there is no central provider `switch`.** Each provider lives in one folder under `Sources/CodexBarCore/Providers/<Name>/` and exposes a `ProviderDescriptor` (single source of truth: id, labels/URLs, branding, capabilities, fetch plan, CLI metadata). A `ProviderFetchPlan` lists allowed `--source` modes and an ordered pipeline of `ProviderFetchStrategy` objects (CLI, browser cookies, OAuth API, local probe, etc.). The CLI and the app both call the same descriptor/fetch pipeline. Descriptors are collected in `ProviderDescriptorRegistry`; the provider enum is `UsageProvider` in `Providers/Providers.swift` (compile-time IDs used for persistence + widgets). UI/settings should be descriptor-driven with minimal per-provider branching. To add a provider, follow `docs/provider.md`.

**Shared host APIs** providers build on: `TTYCommandRunner` (PTY), `SubprocessRunner`, `BrowserCookieImporter` (Safari/Chrome/Firefox), `OpenAIDashboardFetcher` (WKWebView scrape), Keychain access gates, `ProviderHTTPClient`, and the local cost-usage log scanner.

**Identity siloing (hard rule):** identity fields (email/org/plan/loginMethod) must stay siloed per provider. When rendering usage/account info for one provider, never display identity sourced from another (e.g. Claude vs Codex).

## Conventions

- Swift 6 strict concurrency is on for every target. Prefer `Sendable` state and explicit `@MainActor` hops. Treat sibling `async let` (one required + one optional child) as a review red flag — prefer sequential awaits or a drained `withThrowingTaskGroup`; crashes mentioning `swift_task_dealloc` / `asyncLet_finish_after_task_completion` warrant an `async let` audit.
- Prefer modern SwiftUI/Observation: `@Observable` models with `@State` ownership and `@Bindable` in views. Avoid `ObservableObject` / `@ObservedObject` / `@StateObject`. Favor macOS 15+ APIs over deprecated counterparts when refactoring.
- 4-space indent, 120-char lines. Explicit `self` is intentional — do not strip it. Maintain existing `MARK` organization.
- Tests: XCTest/swift-testing under `Tests/CodexBarTests/*Tests.swift` (`FeatureNameTests` with `test_caseDescription`). Platform-agnostic logic also has Linux coverage under `TestsLinux/`. Prefer covering menu behavior through stable model seams (`MenuDescriptor`, `ProvidersPane`, `CodexAccountsSectionState`) rather than live `NSStatusBar`/`NSMenu` flows.
- Model names in code/tests: released or clearly fictitious only — never expose unreleased model names.

## Keychain / live-probe safety

Never run tests, checks, or ad-hoc validation that can trigger macOS Keychain prompts or hit real provider accounts. Live provider probes, browser-cookie imports, `codexbar usage` against real accounts, and real `SecItem` reads must be **explicitly requested**. Otherwise use parser tests, stubs, test stores, or `KeychainNoUIQuery`. Cookie imports default to Chrome-only where possible to avoid other-browser prompts.

## Tooling / dependencies

Use SwiftPM and the provided scripts; do not add dependencies or tooling without confirmation. `CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT=1` swaps the `SweetCookieKit` dependency for a sibling `../SweetCookieKit` checkout when present.

## Notes for agents

- `AGENTS.md` is the upstream agent guide and contains macOS-specific paths (`/Users/steipete/...`) and release/signing details — paths there are not valid in this checkout.
- Per-provider docs live in `docs/<provider>.md`; deeper provider/refactor specs under `docs/refactor/`. `docs/CLAUDE.md` is the detailed Claude-provider spec (not a root config file).
