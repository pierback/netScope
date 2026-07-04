# Handoff

Date: 2026-07-04

## Repository

- Path: `/Users/f.pieringer/projects/netScope`
- GitHub: https://github.com/pierback/netScope
- Branch: `main`
- Purpose: NetScope is a local macOS network diagnosis utility. It provides a Swift CLI and menu bar app backed by `NetScopeCore` to attribute current network pressure to apps while keeping diagnostics lightweight and privacy-preserving.

## Setup, Run, Test

- Run CLI snapshot: `swift run netScope`
- Run menu bar app: `swift run NetScopeMenuBar`
- Test: `swift test`
- Build local app bundle: `./scripts/package-app.sh`
- Open local app bundle: `open .build/NetScope.app`

## Current State

- The repo already had local Git history on `main`; this checkpoint adds the private GitHub origin and pushes the current local state.
- The working tree included an untracked `.codex-fable5/` review ledger/finding state; it is included in this checkpoint.
- README documents the power budget, local baseline privacy, diagnostic inputs, CLI flow, menu bar flow, product scope, and out-of-scope boundaries.
- No verification commands were run as part of this checkpoint/push handoff.

## Known Risks and Open Loops

- `.build` exists locally but is governed by the repo's existing ignore/tracking rules.
- `NetScope` reads local macOS network diagnostics through bounded commands such as `nettop`, `ping`, `route`, and `dig`; behavior should be verified on the target macOS version.
- The app may write learned aggregate baselines under `~/Library/Application Support/NetScope/traffic-baseline.json`; that file is not part of the repo checkpoint.

## Next Steps on Another Mac

1. Clone with `git clone https://github.com/pierback/netScope.git`.
2. Run `swift test`.
3. Run `swift run netScope` while network activity is present.
4. Run `swift run NetScopeMenuBar` to inspect the menu bar workflow.
5. Use `./scripts/package-app.sh` when a local `.app` bundle is needed.
