# CodexBar Windows Engine Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get `CodexBarCLI` (and therefore `CodexBarCore`) building, testing, and returning real usage data on Windows — spec phases 0–1 of `docs/superpowers/specs/2026-06-13-windows-migration-design.md`.

**Architecture:** Extend the existing Linux degradation model (`#if os(Linux)` gates + `.notSupportedOnThisPlatform` errors) to Windows. The spike (Tasks 1–5) is a go/no-go gate; the gating work (Task 6) is iterative by design because the exact error list is unknown until the first Windows build runs.

**Tech Stack:** Swift 6.3.x Windows toolchain (winget), SwiftPM, GitHub Actions `windows-2025`, `compnerd/gha-setup-swift`.

**Scope note:** The C#/WinUI 3 shell (spec phases 2–3) is a separate plan, written after this one lands — its tasks depend on which providers actually work on Windows.

**Known breakage inventory (from repo scan, drives Task 6):**

| Pattern | Count | Windows situation |
| --- | --- | --- |
| `#if canImport(Darwin) import Darwin #else import Glibc #endif` | ~22 files | Neither exists on Windows → add `#elseif canImport(WinSDK)` or `#elseif os(Windows)` branches |
| `import SweetCookieKit` | 34 files | Builds on Linux, unknown on Windows — spike decides |
| `import SQLite3` | 6 files | No system module on Windows → gate behind `#if canImport(SQLite3)` |
| POSIX PTY (`posix_openpt`, `pid_t`) in `Sources/CodexBarCore/Host/PTY/` | 1 area | Stub with `.notSupportedOnThisPlatform` (ConPTY is spec phase 4) |
| POSIX signals in `Sources/CodexBarCLI/CLITerminationSignalMonitor.swift` | 1 file | Gate; Windows path can no-op |
| `import Security` / `LocalAuthentication` / `AppKit` / `WebKit` | ~21 files | Already `os(macOS)`-gated for Linux; verify gates use `os(macOS)` not `!os(Linux)` |

**Conventions reminder:** 4-space indent, 120-char lines, explicit `self`, Swift 6 strict concurrency. Local `make check` tooling is macOS/Linux-pinned; the macOS CI job lints, so keep diffs clean by hand.

---

### Task 1: Install Visual Studio 2022 components (Swift platform dependency)

**Files:** none (machine setup)

- [ ] **Step 1: Install VS 2022 Community with the components Swift requires**

Run (PowerShell, will take 10–20 min; the machine only has Build Tools 2019, which is insufficient):

```powershell
winget install --id Microsoft.VisualStudio.2022.Community --exact --force `
  --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64" `
  --source winget
```

Expected: exit 0, "Successfully installed".

- [ ] **Step 2: Verify the MSVC toolset + Windows SDK landed**

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -products * -latest -property installationPath
```

Expected: a path like `C:\Program Files\Microsoft Visual Studio\2022\Community`.

### Task 2: Install the Swift toolchain

**Files:** none (machine setup)

- [ ] **Step 1: Install via winget**

```powershell
winget install --id Swift.Toolchain -e --source winget
```

Expected: exit 0. Installs the current release (6.3.x as of June 2026).

- [ ] **Step 2: Verify in a NEW terminal session (PATH changes need a fresh shell)**

```powershell
swift --version
```

Expected output shape:

```
Swift version 6.3.x (swift-6.3.x-RELEASE)
Target: x86_64-unknown-windows-msvc
```

If `swift` is still not found, check `%LOCALAPPDATA%\Programs\Swift\Toolchains\` exists and PATH includes its `usr\bin`.

### Task 3: Dependency resolution check

**Files:** none (read-only spike)

- [ ] **Step 1: Resolve SwiftPM dependencies**

From `E:\Work\opensource\CodexBar`:

```powershell
swift package resolve
```

Expected: fetches Sparkle, Commander, swift-crypto, swift-log, swift-syntax, KeyboardShortcuts, Vortex, SweetCookieKit. Resolution should succeed even though some packages are macOS-only — *resolution* is not *compilation*. Record any failure verbatim for the spike report.

### Task 4: Spike build — catalogue everything that breaks

**Files:**
- Create: `docs/superpowers/spikes/2026-06-13-windows-build-spike.md`

- [ ] **Step 1: Attempt the build, capturing the full log**

```powershell
swift build --product CodexBarCLI 2>&1 | Tee-Object -FilePath build-spike.log
```

Expected: FAILURE with many errors (see breakage inventory above). That is the point. Do not start fixing yet.

- [ ] **Step 2: Write the spike report**

Create `docs/superpowers/spikes/2026-06-13-windows-build-spike.md` with this structure, filled from `build-spike.log`:

```markdown
# Windows build spike — 2026-06-13

Toolchain: <swift --version output>

## Verdict: GO / NO-GO (see criteria in plan Task 5)

## Error catalogue

| # | Category | Example error (verbatim) | Files affected | Fix strategy |
| --- | --- | --- | --- | --- |
| 1 | Darwin/Glibc import | ... | ... | add WinSDK branch |
| 2 | SweetCookieKit | ... | ... | conditional dep / gates |
| 3 | SQLite3 | ... | ... | canImport gate |
| 4 | PTY/POSIX | ... | ... | notSupported stub |
| 5 | other | ... | ... | ... |

## Dependency-level results
- swift-crypto: built? Y/N
- swift-syntax macros (CodexBarMacros): compiled and executed? Y/N
- Commander: Y/N
- SweetCookieKit: Y/N — if N, verbatim first error

## Notes for Task 6 ordering
<which category blocks the most files; what to gate first>
```

- [ ] **Step 3: Commit the report (not the log)**

```powershell
git add docs/superpowers/spikes/2026-06-13-windows-build-spike.md
git commit -m "docs: Windows build spike report

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 5: Go/no-go checkpoint — STOP and review with the user

**Files:** none

- [ ] **Step 1: Apply the criteria**

GO if every error category has a known mechanical fix (import gates, `.notSupportedOnThisPlatform` stubs, conditional dependency). NO-GO triggers: macros fail to *execute* on Windows (toolchain-level), swift-crypto or Foundation networking fail to build, or SweetCookieKit fails in a way that conditional-dependency surgery can't isolate (>50 files needing API shims).

- [ ] **Step 2: Present verdict + error catalogue to the user before proceeding.** If NO-GO, return to the spec's rejected-alternatives section with the evidence. If GO, refine Task 6's order using the catalogue.

### Task 6: Apply platform gates iteratively until `swift build --product CodexBarCLI` succeeds

**Files (expected, refine from spike report):**
- Modify: files using Darwin/Glibc imports (~22, e.g. `Sources/CodexBarCore/Host/PTY/TTYCommandRunner.swift`)
- Modify: `Sources/CodexBarCLI/CLITerminationSignalMonitor.swift`
- Modify: SQLite3-importing files (6)
- Modify (only if spike says SweetCookieKit fails): `Package.swift` + the 34 importing files

This task is a loop: fix the top error category → rebuild → repeat. Commit after each category compiles. Use these exact patterns (they mirror the codebase's existing Linux style):

- [ ] **Step 1: Gate Darwin/Glibc import headers**

Pattern — change:

```swift
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
```

to:

```swift
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif
```

For files whose POSIX usage cannot work on Windows at all (PTY), gate the whole implementation instead — see Step 2.

- [ ] **Step 2: Stub the PTY runner on Windows**

In `Sources/CodexBarCore/Host/PTY/TTYCommandRunner.swift`, wrap the existing POSIX implementation in `#if !os(Windows)` and add a Windows stub that preserves the public API. The error type to throw is whatever the existing API surface uses for unsupported platforms — follow `ClaudeWebAPIFetcher.FetchError.notSupportedOnThisPlatform` precedent (see `TestsLinux/PlatformGatingTests.swift:13-26`). Shape:

```swift
#if os(Windows)
public enum TTYCommandRunner {
    // ConPTY port is spec phase 4; CLI probes report unsupported until then.
    public static func run(/* mirror the non-Windows signature exactly */) async throws -> TTYCommandResult {
        throw TTYCommandRunnerError.notSupportedOnThisPlatform
    }
}
#else
// existing implementation, unchanged
#endif
```

Mirror the real signatures from the non-Windows code — do not invent new ones. If `TTYCommandRunnerError` has no `notSupportedOnThisPlatform` case, add one.

- [ ] **Step 3: Gate SQLite3 imports**

Wrap each `import SQLite3` file's functional body: `#if canImport(SQLite3)` around the implementation, `#else` returning empty results or throwing the file's existing error type, matching how that file already degrades on Linux if it does.

- [ ] **Step 4: Gate the CLI signal monitor**

In `Sources/CodexBarCLI/CLITerminationSignalMonitor.swift`, keep POSIX signal handling under `#if !os(Windows)`; the Windows branch installs nothing (process exit handles cleanup). Preserve the public start/stop API.

- [ ] **Step 5: SweetCookieKit — only if the spike says it fails on Windows**

Make the dependency conditional in `Package.swift` (manifests evaluate on the build host):

```swift
#if os(Windows)
let cookieKitDependencies: [Target.Dependency] = []
let cookieKitPackageDependencies: [Package.Dependency] = []
#else
let cookieKitDependencies: [Target.Dependency] = [.product(name: "SweetCookieKit", package: "SweetCookieKit")]
let cookieKitPackageDependencies: [Package.Dependency] = [sweetCookieKitDependency]
#endif
```

and gate the 34 `import SweetCookieKit` sites with `#if canImport(SweetCookieKit)`, stubbing the touched API surface per file with the same degraded-return pattern as Step 3. Budget check: if this exceeds ~50 files of surgery, stop — that was a NO-GO criterion; re-review with the user.

- [ ] **Step 6: Rebuild loop**

```powershell
swift build --product CodexBarCLI
```

Repeat Steps 1–5 categories until: exit 0, binary at `.build\debug\codexbar.exe` (SwiftPM names it per the executable product). Then release build:

```powershell
swift build -c release --product CodexBarCLI
```

Expected: exit 0.

- [ ] **Step 7: Path audit (spec requirement)**

List every filesystem-location lookup and verify each maps sanely on Windows:

```powershell
& "C:\Program Files\Git\bin\bash.exe" -lc "grep -rn 'Library/Caches\|homeDirectoryForCurrentUser\|cachesDirectory\|NSHomeDirectory' Sources/CodexBarCore Sources/CodexBarCLI --include='*.swift'"
```

For each hit confirm: tilde/home → `%USERPROFILE%` (swift-corelibs-foundation handles this), `.cachesDirectory` → `%LOCALAPPDATA%`. Hardcoded `Library/Caches` strings do NOT remap — wrap those in `#if os(macOS)` or switch them to `FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)`. Apply the Task 6 gating patterns; cover any behavior change with a test in `TestsLinux/` (it runs on both Linux and Windows).

- [ ] **Step 8: Commit per category**

One commit per error category fixed, e.g.:

```powershell
git add -A
git commit -m "port: gate PTY runner for Windows

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 7: Extend platform-gating tests to Windows and run the suite

**Files:**
- Modify: `TestsLinux/PlatformGatingTests.swift`

- [ ] **Step 1: Widen the Linux-only expectations to Windows**

In `TestsLinux/PlatformGatingTests.swift`, change every `#if os(Linux)` to `#if os(Linux) || os(Windows)` (3 sites: lines 14, 30, 39). The assertions are identical — web fetchers must throw `.notSupportedOnThisPlatform` on both platforms.

- [ ] **Step 2: Run the test to verify it passes on Windows**

```powershell
swift test --filter PlatformGatingTests
```

Expected: PASS (3 tests). If `.notSupportedOnThisPlatform` is not thrown on Windows, the gates from Task 6 missed the Claude web fetcher — fix there, not in the test.

- [ ] **Step 3: Run the full portable suite**

```powershell
swift test --parallel
```

Expected: PASS. (`CodexBarLinuxTests` is the only test target SwiftPM builds on non-macOS hosts — see `Package.swift:82-89`.) Catalogue and fix any failures with the Task 6 patterns.

- [ ] **Step 4: Commit**

```powershell
git add TestsLinux/PlatformGatingTests.swift
git commit -m "test: extend platform gating expectations to Windows

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 8: Live smoke test — REQUIRES EXPLICIT USER CONSENT

**Files:** none

Per CLAUDE.md, hitting real provider accounts must be explicitly requested. Ask the user before this task; skip it if declined (CI green is the merge gate, not this).

- [ ] **Step 1 (after consent): run usage against the local Claude OAuth credentials file**

```powershell
.\.build\release\codexbar.exe usage --provider claude --json
```

Expected: JSON with `provider: "claude"`, populated `usage` (session/weekly percentages) sourced from `%USERPROFILE%\.claude\.credentials.json` via the OAuth strategy. An auth error is acceptable (means plumbing works); a crash or path error is a bug — fix with Task 6 patterns.

- [ ] **Step 2 (after consent): smoke the serve seam the shell will use**

```powershell
Start-Process -NoNewWindow .\.build\release\codexbar.exe -ArgumentList "serve","--port","8765"
Invoke-RestMethod http://127.0.0.1:8765/health
Invoke-RestMethod "http://127.0.0.1:8765/usage?provider=claude"
Stop-Process -Name codexbar -Force -Confirm:$false
```

Expected: `/health` returns `{"status":"ok"}`-shaped payload; `/usage` returns the provider payload array.

### Task 9: Add the Windows CI job

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add the job (mirrors the Linux job's role)**

Append to `jobs:` in `.github/workflows/ci.yml`:

```yaml
  cli-windows:
    name: CLI (Windows)
    runs-on: windows-2025
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: compnerd/gha-setup-swift@main
        with:
          branch: swift-6.2.1-release
          tag: 6.2.1-RELEASE
      - name: Swift version
        run: swift --version
      - name: Build CLI (release)
        run: swift build -c release --product CodexBarCLI
      - name: Test
        run: swift test --parallel
```

Note the version pin: CI pins 6.2.1 to match the Linux job even though the local spike used 6.3.x. If 6.2.1 fails on errors that 6.3.x fixed, bump BOTH the Linux and Windows pins in the same commit and say so in the commit message.

- [ ] **Step 2: Commit and push**

```powershell
git add .github/workflows/ci.yml
git commit -m "ci: build and test CodexBarCLI on Windows

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin windows-migration
```

- [ ] **Step 3: Verify the job goes green**

```powershell
gh run watch --branch windows-migration
```

Expected: `cli-windows` PASS. Existing macOS + Linux jobs must also stay green — the gates added in Task 6 must not change non-Windows behavior (they are additive `#elseif`/`#if os(Windows)` branches).

---

## Done criteria (phase 1 of the spec)

- `swift build -c release --product CodexBarCLI` exits 0 on Windows (local + CI).
- `swift test --parallel` passes on Windows (local + CI).
- macOS and Linux CI unchanged and green.
- Spike report committed; gates follow the Linux degradation pattern.
- Next plan: C#/WinUI 3 shell MVP (spec phase 2), written against the now-known Windows provider surface.
