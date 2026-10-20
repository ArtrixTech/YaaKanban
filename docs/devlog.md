# Devlog

## feat(integrations): add agent installers and yaak CLI

`pending` | 2026-10-20

- **Changes**: YaaIntegrations: Claude/Codex (Claude-shaped hooks.json), Cursor hooks.json, OpenCode + pi plugin files; idempotent plan/apply with `.yaak.bak` backups and `--dry-run`. CLI `yaak hook|install|uninstall|status`; permission hook blocks up to 25 s for an app decision (Claude, OpenCode), spools when the app is down. Snapshot events no longer count as activity for hooked sessions.
- **Reason**: Spec §3 transport and installer safety.
- **Process**: Temp-HOME tests for every installer. Plugins checked by stripping TS types (node 22) + `node --check`, then driven with a fake pi object end to end into the spool.
- **Result**: `make test` 26/26. pi event order verified (prompt → tool_start → tool_end → turn_end).
- **Notes**: `FileManager.homeDirectoryForCurrentUser` ignores `$HOME`; a dry-run under a fake HOME read the real settings.json (no write). All home lookups now go through `Paths.home`. Concurrent `spawn` in plugins reordered events; plugins now chain sends and stamp `ts`. `unref()` on the child let node exit before the chain drained, so it was removed.

## feat(core): add event model, reducer, stuck detection, wire, store

`pending``5c7406b` | 2026-10-20

- **Changes**: Scaffold SwiftPM package (YaaCore, YaaIntegrations, yaak, YaaKanban), AGENTS.md from artrix-skills `9f9d782`, spec, Makefile. YaaCore: JSONValue, models, normalizers (Claude/Codex schema, Cursor, yaak plugin schema), SessionReducer + Alerts, StuckDetector, Unix socket client/server + spool, SQLite Store.
- **Reason**: Foundation for the cross-agent monitor agreed in the grilling session (see `docs/spec.md`).
- **User feedback**: "快速写个程序，用来监控各个harness下的任务情况…和我用grilling对齐。" Then "agents.md用artrixskills的。然后开干，做好工作流。"
- **Process**: Hook schemas verified from local installs: Claude settings.json, Codex binary strings (PreToolUse/PermissionRequest/…; `tool_use_id`, `last_assistant_message`), OpenCode plugin SDK 1.2.10 types, pi 1.3.0 extension docs. CLT lacks a default Swift Testing path; Makefile passes `-F` + rpath.
- **Result**: `make test` 19/19 pass.
- **Notes**: Synthetic tool ids must be process-stable (FNV-1a), since pre/post hooks run in separate `yaak` processes. A research sub-agent accidentally ran `adrafinil install-hooks` (no `--help` support) and rewrote Adrafinil entries in the user's agent configs; files verified valid, user informed.
