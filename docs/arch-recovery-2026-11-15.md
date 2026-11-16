# Continuation result — 2026-11-15

Latest full run: **147 passed, 0 failed, 1 skipped**. The remaining skip is
mason_install_enables_server because vtsls is already installed. Go, Rust, C#,
TypeScript, Java, Lua, C++, Python and Astro highlighting/LSP/definitions all run and pass.
The earlier result below is historical evidence, not the current test status.

Source changes: project.lua bounds root markers at the nearest Git repository;
debugging.lua sets both cwd and dlvCwd for the selected Go package. check.lua
adds nested Git/worktree/workspace regressions and isolates PATH/buffer lifecycle
fixtures without removing assertions. The debugger check retains its stopped
statusline assertion and waits for the existing scheduled UI refresh.

`timeout 200s nvim --headless -n -i NONE '+luafile tests/mixed-languages.lua'`
passes highlighting, server/root selection, definitions, local-function completion
and C# client reuse across a temporary mixed C#/TS/Go repository. Requires real
servers: absence is a failure, not a silent skip. Real Python, Astro, and mixed-language personal projects were also opened for
read-only highlighting, hover/K and definition probes; project Git states were unchanged.

Local prerequisites installed: tree-sitter-cli 0.26.9-1, Delve 1.27.1-1,
JDK25 25.0.5.0.3.u1-1; Mason csharp-ls 0.24.0, vtsls 0.3.0, jdtls v1.63.0;
rust-analyzer component for existing stable 1.99.1; configured parsers from the
unchanged plugin lock. Project SDK selection and Mason PATH append unchanged.
Old Go-installed Delve remains on disk. The old binary rejected Go 1.27.3;
compatible Delve then exposed the separate package build-directory defect.

Warm root lookup median decreased from 0.340 to 0.132 ms (9 alternating runs,
150 Lua/Go/Rust lookups each). Warm-cache headless startup comparison (21 balanced
pairs, same tools): VimEnter medians 8.87/8.94 ms; deferred LSP discovery
26.07/26.13 ms before/after, within observed variability. Not GUI or large-project
benchmarks. Ubuntu/WSL remains unverified; no universal performance guarantee.

Continuation backup: ~/.local/state/dev-environment-recovery/continuation-20261115-160125/.
Restore individual original source/test/doc files after preserving later edits;
move aside the new mixed-language test if undoing it. Provisioning rollback is
separate: review package dependents, remove only the new Mason servers or stable
rust-analyzer component if desired, and use the plugin's parser uninstall interface
for the newly recorded set. No rollback execution or offline completeness claim.
Private logs/receipts/grammar metadata are retained with that snapshot.

The environment repository's continuation note contains primary references,
intermediate failures, detailed timing spread and the remaining desktop/platform
acceptance gaps. No plugins were upgraded and no implementation was moved there.


## Python, Astro and CI follow-up

Python now enables existing Pyright alongside Ruff. Ruff's advertised hover is
for lint directives, not ordinary symbols; K reports the missing semantic server
when only Ruff is available. Health advice gives actual Mason package names.
Astro now enables astro-ls, discovers a bounded project TypeScript SDK before
its existing Mason fallback, and reports an unavailable explicit SDK. Managed
Tree-sitter parser and query installation shares the standard data/site path;
a legacy Astro parser without its queries no longer counts as syntax support.
Checks assert actual highlight captures. Missing CLI/unsupported syntax is reported.

Dependabot PR #2 exposed a long-branch statusline defect, reproduced at 80 columns.
Branch text is bounded when the cached statusline updates, including on resize;
new 60/80-column checks preserve filename visibility and literal percent signs.
No cursor-redraw Lua callback was added. Full `./tests/check.sh`: 147/0/1;
the skip is the already-installed vtsls installation scenario, not a language skip.

Warm Python/Astro startup, 21 balanced pairs: first frame medians 9.19/9.13 ms;
deferred server discovery 26.07/27.50 ms with overlapping ranges (23.60–33.54 /
24.52–32.80 ms). Nine alternating syntax callback runs, 150 events each:
0.0121/0.0122 ms median. These do not prove cold-cache or GUI performance.

Limitations: no universal declared-version enforcement, pinned fallback tool
manifest, live devshell transition or project-local-only server discovery yet.
Parser downloads/builds remain runtime requirements. Ubuntu/WSL, clean install,
overrides/opt-out and full offline behavior remain unverified. Nix packaging was
not built locally. Existing Go behavior is covered by the full suite and real project.

Backups for these changes are in private recovery snapshots named python,
astro and continuation under the existing recovery state directory. Restore only
the affected files after preserving newer edits; parser quarantine and package
provisioning are separate host-state rollback steps. A code revert does not undo
Mason packages or compiled parsers. Do not remove working project toolchains.

---

# Arch parser recovery — 2026-11-15

Tested source baseline: 4b3c92c6fbe9bf5e80cb6d4b03379a592702b774,
plus uncommitted tests/parser-query-check.lua. Existing nvim.log preserved.
Neovim 0.12.6-1; nvim-treesitter installed/locked commit
04f17886f75416dfdc25374c950a52c63f0e98fe.

The plugin directory retained an untracked parser/lua.so from an older install
(parser-info/lua.revision db16e76558122e834ee214c8dc755b4a3edc82a9).
Its grammar lacks operator fields required by current Lua queries.
Explicitly loading it in clean Neovim reproduces the invalid-field error.
The packaged parser handles the queries. The installed executable and Lua query
SHA256 hashes match pacman's local mtree entries; no reinstall was performed.

Only the stale Lua parser was quarantined, into a private recovery snapshot under
~/.local/state/dev-environment-recovery/20261115-154246/. No plugin upgrades,
lockfile changes or Go configuration changes. No portable parser preference was
introduced: machines without a packaged parser still use their installed parsers.

Run the regression check with:

```sh
timeout 10s nvim --headless -n -i NONE '+luafile tests/parser-query-check.lua'
```

It compiles Lua highlighting/injection queries and starts highlighting after
loading the plugin and opening another buffer. CHECK_PARSER can explicitly select
a parser for diagnostics. Against the backed-up stale-lua.so it exits 1 with the
operator-field error; against the repaired runtime it exits 0.

`timeout 180s tests/check.sh` finished: 128 passed, 4 failed, 4 skipped.
Go/Lua/C++ highlighting, LSP and definitions pass. Failures:

- parsers_installed: plugin-managed parser installation set absent; tree-sitter
  CLI absent. Existing/system parser highlighting passing is a separate result.
- project_root_nearest: config source resolves to the home directory rather than
  its repository. Root-cause diagnosis outstanding; do not weaken the assertion.
- debug_session_stops_at_breakpoint: launch failed and its 90-second wait expired.
- no_error_messages: the debugger's two launch-error messages.

The initial 45-second bounded run expired during the broader suite; the 180-second
run completed. Its raw output is retained privately as recovery-nvim-full.log in
the snapshot. No overall green baseline is claimed.

Rust LSP skips: active stable toolchain lacks rust-analyzer; fallback alternates
between two rustup proxy locations and reports infinite recursion. No toolchain
installed or changed. C#/TypeScript/Java LSP servers skip as absent.
Ubuntu/WSL, clean install, upgrade, offline completeness, external overrides,
opt-out and rollback execution remain unverified. Nix is deferred.

Rollback: preserve newer edits, then copy stale-lua.so from the snapshot back to
~/.local/share/nvim/lazy/nvim-treesitter/parser/lua.so (reintroduces the failure).
The only source addition is the regression check; move it aside to undo that
addition. Backups of source files before work are in the snapshot's .config/nvim.

Next: diagnose project root selection and isolate the real Delve launch failure
with retained DAP logs. Establish parser installation prerequisites separately;
do not upgrade all plugins or replace project toolchains to obtain green checks.

## CI follow-up — 2026-11-16

PR #4's Ubuntu Linux job failed its mandatory Python hover regression because
setup supplied LuaLS but no Pyright. Setup now installs Pyright 1.1.407 explicitly;
the same installation passed the local hover regression. This is a test prerequisite,
not a global project SDK replacement. Parser restore now disables implicit downloads
and runs one explicit, failure-propagating provisioning step. A public-process
regression proves the opt-out preserves existing highlighting without installing.

Local Go debug verification exposed an async nvim-dap statusline race: stopped
events can yield before frame state is ready. Refresh again after the scopes
response, without polling. The existing breakpoint/statusline assertion failed
before and passed after. A separate invalid /tmp/.git marker interfered with Go's
VCS stamping; tests used a clean private TMPDIR rather than changing Git or
disabling VCS checks. Full Arch suite: 147 passed, 0 failed, 1 skipped; all twelve
tripwires detected their intended violations. Explicit provisioning verified all
31 configured parsers and download-opt-out regression passed. The remaining skip
is the already-installed vtsls installation scenario. Hosted CI awaits rerun;
these local results do not establish Ubuntu/WSL or clean offline provisioning.

Rollback: CI follow-up originals are in the private recovery ci-20261116-104141
snapshot. Restore individual affected files after preserving subsequent changes,
and move the two added parser test scripts aside if reverting the workflow.
Untracked nvim.log was preserved and excluded.
