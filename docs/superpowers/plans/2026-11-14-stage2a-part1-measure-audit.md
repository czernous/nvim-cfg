# Stage 2a Part 1 — Measure, Enforce, Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the measured baseline, the standards checks (each proven by a tripwire), the step‑1 leftovers, and the plugin audit + plugin‑manager spike the owner approves before any plugin changes.

**Architecture:** `tests/bench.lua` (run by `tests/bench.sh`) spawns child Neovims and records medians/spreads to JSON; standards checks live in `tests/check.lua` beside the existing 56, with deliberate violations in `tests/tripwires/` that `tests/check.sh --tripwires` proves are caught. Candidate plugins are measured in a sandbox (`XDG_*` dirs under the scratchpad), never in the owner's live config. Outputs: `docs/perf/baseline.md`, `docs/perf/audit.md`, `docs/adr/0001-plugin-manager.md` (draft).

**Tech Stack:** Neovim 0.12.4 (LuaJIT), lazy.nvim, sh.

**Spec:** `docs/superpowers/specs/2026-11-14-stage2a-lean-core-design.md`

## Global Constraints

- No plugin added to or removed from the live config in this plan (audit only); live config changes are limited to Tasks 2–3 (standards fixes, step‑1 leftovers).
- Benchmarks run with the owner's real interactive `$PATH`; every number = median of ≥10 runs + spread (min–max); a number is reported only when two separate runs agree within 15%.
- No blocking calls (`vim.fn.system/systemlist/executable/exepath`, `io.popen`, `os.execute`, `vim.system():wait()`) at startup or on hot paths in config code, except sites in `tests/standards-allowlist.lua` with a reason each.
- No OS/machine-specific code; no hard-coded SDK versions or paths; missing external tools → one warning + fallback.
- Sandboxes and downloaded candidate plugins/tools live under the session scratchpad (`$SCRATCH`), never on the owner's `$PATH` or in `~/.local/share/nvim`.
- `./tests/check.sh` green at the end of every task; commits use `-c user.name='Anton Chernous' -c user.email=czernous_a@hotmail.com` and the trailer `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.
- Every new check is shown failing (RED) before it passes; every fitness check additionally has a tripwire.

## Review Focus

1. **Benchmark noise:** two consecutive `bench.sh` runs on an idle machine disagree by >15% → the script must say "unstable" rather than print a number. Pinned in Task 1 (`bench_reports_instability`).
2. **Memory check false alarms:** LuaJIT/allocator noise makes a leak bound flaky → the bound uses a full `collectgarbage('collect')` twice and a tolerance measured from 3 clean runs. Pinned in Task 2 (`no_buffer_state_leaks` passes 3× in a row on clean code).
3. **Tripwire that can't trip:** a fitness scanner that ignores the tripwire's path → `--tripwires` mode must show each check FAILING. Pinned in Task 2.
4. **`:MasonInstall` mid-session:** installing a server while a buffer of that language is open → it attaches without restart and without a blocking lookup. Pinned in Task 3 (`mason_install_enables_server`).
5. **Sandbox leaking into the live setup:** spike/audit runs must not write to `~/.local/share/nvim`, `~/.cache/nvim`, or `lazy-lock.json` → Task 4/5 assert unchanged mtimes/hashes afterwards.

---

### Task 1: Benchmark harness and baseline

**Files:**
- Create: `tests/bench.sh`, `tests/bench.lua`, `docs/perf/baseline.md`, `tests/bench/.gitignore` (ignores raw `*.json` except `baseline.json`), `tests/bench/baseline.json`

**Interfaces:**
- Produces: `./tests/bench.sh [--runs N] [--label L] [--config DIR]` → writes `tests/bench/<label>.json` = `{ startup_ms = {median,min,max}, open_ms = {<lang> = {median,min,max}}, completion_ms = {lua=…, go=…}, alloc_bytes_per_event = {CursorMoved=…, TextChangedI=…, statusline=…}, stable = bool }`; `--config DIR` runs against another config root via `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME`/`XDG_CACHE_HOME` (used by Tasks 4–5).
- Measures:
  - `startup_ms`: `nvim --headless --startuptime f +qa`, "NVIM STARTED".
  - `open_ms[lang]`: child `nvim --headless <fixture>`; time from `vim.v.vim_did_enter`-time hrtime recorded in `--cmd` to `vim.treesitter.highlighter.active[buf]`.
  - `completion_ms[lua|go]`: fixture with server attached and warmed; insert a prefix; time from keystroke to completion menu visible. "Visible" via an adapter table keyed by engine (`nvim-cmp`: `require('cmp').visible()`; built-in/pum: `vim.fn.pumvisible()==1`; others added in Task 4).
  - `alloc_bytes_per_event`: `collectgarbage('stop')`, record `collectgarbage('count')`, fire the event 1000× (`nvim_exec_autocmds` for CursorMoved / TextChangedI in a fixture buffer; `nvim__redraw({statusline=true})` for statusline), delta×1024/1000; restart GC.
  - `stable`: run whole suite twice; false if any median differs >15%.

- [ ] **Step 1: Write failing check** `bench_reports_instability` in `tests/check.lua`: run `tests/bench.lua`'s `compare(a, b)` on two synthetic results differing by 20% → returns `stable=false`; differing 5% → `true`.
- [ ] **Step 2: Run** `./tests/check.sh` → FAIL (module missing).
- [ ] **Step 3: Implement** `tests/bench.lua` + `tests/bench.sh` as specified.
- [ ] **Step 4: Run** `./tests/check.sh` → PASS; run `./tests/bench.sh --label baseline` twice; expected `stable=true`; startup median ≈110 ms (step‑1 measurement).
- [ ] **Step 5: Write** `docs/perf/baseline.md` (table of all numbers with spread, machine facts: CPU, WSL, `$PATH` entry count, Neovim version) — numbers copied from `baseline.json`, nothing estimated.
- [ ] **Step 6: Commit** — `perf: benchmark harness and baseline`.

### Task 2: Engineering-standards checks with tripwires

**Files:**
- Modify: `tests/check.lua`, `tests/check.sh` (add `--tripwires`), `lua/czernous/incremental_selection.lua` (leak fix), any config file the new checks flag
- Create: `tests/standards-allowlist.lua`, `tests/tripwires/lua/czernous/tripwire_blocking.lua`, `tripwire_global.lua`, `tripwire_reflection.lua`, `tripwire_deprecated.lua`, `tripwire_leak.lua`

**Interfaces:**
- Consumes: `check.recorded`, `check.exe_calls` (existing harness).
- Produces checks: `no_blocking_calls`, `no_global_writes`, `no_reflection`, `no_deprecated_api`, `no_buffer_state_leaks`. Tripwire mode: `CHECK_TRIPWIRE=<name> ./tests/check.sh` prepends `tests/tripwires` to `runtimepath` and `require`s `czernous.tripwire_<name>` at startup, and the scanners treat `tests/tripwires/lua/**` as config code. `./tests/check.sh --tripwires` runs each mode and exits non-zero unless every tripwire makes exactly its target check FAIL.
- Mechanics (decided):
  - blocking: wrap `vim.fn.system/systemlist/executable/exepath`, `io.popen`, `os.execute`, and `vim.SystemObj.wait` in `--cmd`; record caller source via `debug.getinfo(2,'S')`; config-source calls during startup or inside `CursorMoved`/`TextChanged*`/statusline evaluation fail unless `standards-allowlist.lua` lists `{file, func, reason}`.
  - globals: `setmetatable(_G, { __newindex = recorder })` in `--cmd`; writes from config sources fail. Static scan of `lua/`, `after/` for `_G%.` too.
  - reflection: static scan of `lua/`, `after/` (and tripwire dir in tripwire mode) for `debug%.`, `loadstring`, `load%(`, `setfenv`, `getfenv`.
  - deprecated: static scan for `vim%.loop`, `vim%.lsp%.get_active_clients`, `vim%.lsp%.buf_get_clients`, `vim%.diagnostic%.goto_`, `vim%.tbl_islist`, `vim%.highlight%.on_yank`, `nvim_buf_get_option`, `nvim_buf_set_option`; plus `:checkhealth vim.deprecated` output must not mention config files.
  - leaks: in a scratch copy of the lua fixture, 100× (`:edit` new file, `<C-space>` selection, `:bwipeout`); full collect twice; Lua memory growth ≤ the tolerance (3 clean-run max growth × 2, recorded in the check).

- [ ] **Step 1: Write the five checks and five tripwires.**
- [ ] **Step 2: Run** `./tests/check.sh` → expected RED: `no_buffer_state_leaks` (incremental_selection keeps per-buffer nodes), plus whatever else the scanners find in the current config — record each finding in the commit body.
- [ ] **Step 3: Run** `./tests/check.sh --tripwires` → each tripwire makes its target check FAIL (prove the scanners work).
- [ ] **Step 4: Fix findings in config code** — incremental_selection clears `selections[buf]` on `BufWipeout`/`BufDelete` (augroup, buffer-local); other findings fixed or allowlisted with a reason (only the existing async-by-design sites may be allowlisted, e.g. `format.lua` `vim.system` with callback is not blocking and needs no entry).
- [ ] **Step 5: Run** `./tests/check.sh` → all PASS; run it 3× to confirm `no_buffer_state_leaks` is stable; `--tripwires` still all trip.
- [ ] **Step 6: Commit** — `test: standards fitness checks with tripwires; fix buffer-state leak`.

### Task 3: Step‑1 leftovers

**Files:**
- Modify: `lua/czernous/plugins/ui.lua`, `tests/check.lua`, `tests/fixtures/csharp/fixture.csproj`, `lua/czernous/lsp.lua`, `lua/czernous/format.lua`

**Interfaces:**
- `lsp.lua`: on Mason's `package:install:success` event (mason-registry), if the package provides a server program listed in `M.servers`, run the same background lookup for that one program and `vim.lsp.enable` it (no blocking calls).
- `format.lua`: Spotless detection = root `gradlew` + "spotless" found in root build file **or** any `*/build.gradle(.kts)` one level down **or** `buildSrc/**`/`build-logic/**` `*.gradle.kts`/`*.kt` — read asynchronously or cached per root (no repeated file reads per format); non-executable `gradlew` → one WARN naming the file, then LSP fallback.

- [ ] **Step 1: Write failing checks**: `lualine_follows_theme` (`require('lualine').get_config().options.theme == 'auto'`); fix vacuous checks — `direct_open_attaches` reports SKIP when lua_ls missing; `which_key_groups_used` is computed from `M.prefixes` against `M.all()` independently of `M.which_key()` and its tripwire (a prefix with no keys) makes it fail; `rootless_file_is_quiet` also asserts a highlighter; `no_prefix_clashes` also flags live mappings that are a strict prefix of a user lhs; `csharp_fixture_unpinned` (csproj has no literal `net\d`); `mason_install_enables_server` (fire a fake `package:install:success` for a package whose bin is a temp executable named like a listed server → server enabled within 2 s); `spotless_in_subproject_detected`, `spotless_gradlew_not_executable_warns` (fake projects as in step 1).
- [ ] **Step 2: Run** → each FAILs for the stated reason.
- [ ] **Step 3: Implement.** C# fixture: `<TargetFramework>net$(BundledNETCoreAppTargetFrameworkVersion)</TargetFramework>`.
- [ ] **Step 4: Run** `./tests/check.sh` and `--tripwires` → PASS.
- [ ] **Step 5: Commit** — `fix: step-1 review leftovers`.

### Task 4: Plugin audit

**Files:**
- Create: `docs/perf/audit.md`, `tests/bench/candidates/<name>/` sandbox configs (gitignored), candidate result JSONs (gitignored; numbers copied into the audit)

**Interfaces:**
- Consumes: `bench.sh --config DIR --label L`.
- For each current plugin (30 in `lazy-lock.json`): role for the owner (which keys/features use it), startup cost (`--startuptime` per-plugin lines + lazy.nvim profile), build/download needs, built-in alternative in 0.12, verdict (keep / lazy-load trigger / replace with X / drop) + reason + risk.
- Candidates measured in sandbox configs (copy of the live config with one area swapped; plugins fetched into the sandbox's `XDG_DATA_HOME`): completion = nvim-cmp (current) vs blink.cmp (Lua fuzzy, `fuzzy.implementation = 'lua'`) vs built-in `vim.lsp.completion`; picker = Telescope (current) vs Telescope without fzf-native vs fzf-lua (with an `fzf` binary placed only on the sandbox's PATH); formatting = Neoformat+format.lua vs conform.nvim (cost only); theme = onedark vs `mini.base16` with a One Dark base16 palette. Each candidate's `completion_ms`, `startup_ms`, `alloc_bytes_per_event` with spread.
- Audit also lists: which external tools each verdict requires (e.g. `fzf`) for owner acceptance, and every key whose implementation would change.

- [ ] **Step 1: Snapshot** hashes/mtimes of `~/.local/share/nvim`, `~/.cache/nvim`, `lazy-lock.json` (Review Focus 5).
- [ ] **Step 2: Build sandboxes and run** `bench.sh --config` for each candidate (2 runs each; unstable numbers re-run or reported as unstable).
- [ ] **Step 3: Write** `docs/perf/audit.md` (one table row per plugin + a candidates section with numbers and spreads + recommendations).
- [ ] **Step 4: Verify** snapshot unchanged.
- [ ] **Step 5: Commit** — `docs: plugin audit with measured candidates`.

### Task 5: Plugin‑manager spike

**Files:**
- Create: `docs/adr/0001-plugin-manager.md` (status: proposed), sandbox under `$SCRATCH/spike-pm/` (not committed)

**Interfaces:**
- Two sandbox variants of the live config: (A) lazy.nvim as today; (B) built-in `vim.pack` + a ≤100-line lazy-load helper (`on key/cmd/ft/event → packadd`).
- Each variant must: (1) install from its lockfile on a clean sandbox; (2) run `tests/check.sh` green (via `--config`); (3) run with **network disabled** (`GIT_ALLOW_PROTOCOL=none`, `http_proxy=https_proxy=http://127.0.0.1:9`) from a mock Nix-style packpath `$SCRATCH/spike-pm/nixpack/pack/nix/opt/<plugin>` containing the same plugin checkouts — same Lua config, zero network access, still lazy-loading; (4) bench startup.
- ADR records: options, results table (pass/fail per criterion, startup ms), recommendation, consequences for stage 2c/3.

- [ ] **Step 1: Build variant A and B; run criteria 1–4**, record results.
- [ ] **Step 2: Verify** Review Focus 5 snapshot unchanged.
- [ ] **Step 3: Write** ADR 0001 (proposed).
- [ ] **Step 4: Commit** — `docs: plugin manager spike (ADR 0001, proposed)`.

### Task 6: Owner checkpoint

- [ ] **Step 1:** Present to the owner: baseline numbers, standards findings fixed, audit verdict table, candidate numbers, required external tools, key changes, ADR 0001 recommendation. Owner approves/vetoes each verdict.
- [ ] **Step 2:** Record decisions in `docs/perf/audit.md` ("Owner decision" column) and set ADR 0001 to accepted/rejected. Commit — `docs: owner decisions on stage 2a audit`. Part 2 plan (implementation) is written from these decisions.
