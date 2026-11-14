# Step 1 — Working, Modular Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every language the owner uses (Go, Rust, C#, JS/TS, Java, Lua) works from servers on `$PATH`, in a config where each file has one job and every keymap is described and clash-free.

**Architecture:** A headless check script (`tests/check.lua`) is written first and drives every task. Plugin specs own their setup and keys (the `cfg/` folder is dissolved). LSP servers are enabled from one list in `lua/czernous/lsp.lua` when their executable exists; per-server tweaks live in `after/lsp/<server>.lua`. Theme and transparency live in `lua/czernous/theme.lua`.

**Tech Stack:** Neovim 0.12, Lua, lazy.nvim, nvim-lspconfig (configs only, via `vim.lsp.config`/`vim.lsp.enable`), mason.nvim (fallback only), nvim-treesitter `main`.

**Spec:** `docs/superpowers/specs/2026-11-14-step1-modular-working-config-design.md`

## Global Constraints

- Neovim ≥ 0.12; plugin manager stays lazy.nvim; namespace stays `czernous`.
- No OS/machine checks (no `has('wsl')`, hostnames, home paths) and no hardcoded language/SDK versions or JDK paths anywhere.
- Servers come from `$PATH`; Mason has no `ensure_installed`, `PATH = "append"`; `mason-lspconfig` removed.
- No error notifications when a tool/server/parser is missing or broken.
- Every user-defined keymap has a `desc`; no user lhs is both a complete mapping and a prefix of another mapping in the same mode; no buffer-local user mapping shadows a global user mapping with a different meaning.
- Keys the owner uses stay unchanged: `<leader>pf <leader>pv <leader>pg <leader>ps <C-p> <leader>s <leader>y <leader>Y <leader>p <leader>a <C-e> <leader>1-4 <leader>u <leader>gs <C-d> <C-u> n N J Y`. Any other changed key is listed in the README "Changed keys" section.
- Plugins are not swapped in this step (except removing `mason-lspconfig`); behaviour stays onedark (`style = 'warm'`).
- Each task ends with `./tests/check.sh` green (or failing only on checks owned by later tasks, which the task lists) and a commit using identity `-c user.name='Anton Chernous' -c user.email=czernous_a@hotmail.com` and the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Server executable exists but fails at start** (this machine's `rust-analyzer` rustup proxy, missing component) → at most one WARN, no ERROR, no retry loop. Pinned in Task 3 (`broken_server_is_quiet`).
2. **Single file outside any project** (`/tmp/x.go`, no `go.mod`) → buffer opens, highlighting works, no error. Pinned in Task 3 (`rootless_file_is_quiet`).
3. **Non-file buffers** (`:help`, netrw `:Ex`, `:terminal`, `[No Name]`) → treesitter/transparency/LspAttach autocmds raise nothing. Pinned in Task 5 (`special_buffers_are_quiet`).
4. **No `tree-sitter` CLI on PATH** and a filetype without a parser → no install attempt, no error. Pinned in Task 4 (`no_cli_no_install`).
5. **Java with `JAVA_HOME` unset** (this machine) → jdtls still starts using the `java` on PATH; no hardcoded runtime path. Pinned in Task 3 (`jdtls_no_hardcoded_runtime`).

---

## File Structure (end state)

```
init.lua                         require('czernous')
lua/czernous/init.lua            load order: options, keymaps, lazy, theme, lsp
lua/czernous/options.lua         (was set.lua) options + diagnostic display
lua/czernous/keymaps.lua         (was remap.lua) THE single keymap registry — every key, grouped by purpose
lua/czernous/lazy.lua            bootstrap + setup('czernous.plugins')
lua/czernous/theme.lua           colorscheme + transparency (single theme spot)
lua/czernous/lsp.lua             server list, PATH-based enable, LspAttach keys, format
lua/czernous/plugins/ui.lua          onedark, catppuccin, lualine, devicons, which-key
lua/czernous/plugins/editor.lua      harpoon, undotree, sleuth, neoformat
lua/czernous/plugins/git.lua         fugitive, rhubarb, gitsigns
lua/czernous/plugins/search.lua      telescope, fzf-native (+ old telescope-config contents)
lua/czernous/plugins/treesitter.lua  treesitter, textobjects, context, incremental selection
lua/czernous/plugins/completion.lua  nvim-cmp, luasnip, sources (+ old autocompletion-config)
lua/czernous/plugins/lsp.lua         nvim-lspconfig, mason, lazydev, fidget
lua/czernous/plugins/diagnostics.lua trouble
after/lsp/rust_analyzer.lua  after/lsp/lua_ls.lua  after/lsp/jdtls.lua
tests/check.sh  tests/check.lua  tests/fixtures/{go,rust,csharp,ts,java,lua}/
```
Deleted: `lua/czernous/cfg/`, `set.lua`, `remap.lua`, old plugin files merged above, `.luarc.json` (lazydev covers it).

---

### Task 1: Headless check harness and fixtures

**Files:**
- Create: `tests/check.sh`, `tests/check.lua`, `tests/fixtures/go/{go.mod,main.go}`, `tests/fixtures/rust/{Cargo.toml,src/main.rs}`, `tests/fixtures/csharp/{fixture.csproj,Program.cs}`, `tests/fixtures/ts/{package.json,tsconfig.json,index.ts}`, `tests/fixtures/java/src/Main.java`, `tests/fixtures/lua/init.lua`

**Interfaces:**
- Produces:
  - `tests/check.sh [--keymaps]` → runs `nvim --headless --cmd "luafile tests/check.lua"` from the repo root; exit 0 = all pass. With `--keymaps`, prints a Markdown keymap table instead (used in Task 7).
  - In `check.lua`: `check.global(name: string, fn: fun(): (ok: boolean, msg?: string))` and `check.lang{ name, file, server, exe, timeout_ms }`. Every later task adds checks by calling these.
  - Recorded keymaps: `check.recorded` = list of `{mode, lhs, desc?, buffer?, src}` captured by wrapping `vim.keymap.set` in `--cmd` (before init) and keeping calls whose `debug.getinfo(2,'S').source` is under the config dir (excluding `tests/`).
  - Error capture: wrap `vim.notify` and read `:messages`; any level ≥ `ERROR`, or any message matching `^E%d+:` / `Error`, fails the run.
- Output format per check: `PASS name`, `FAIL name: msg`, `SKIP name: <exe> not on PATH`; final `N passed, M failed, K skipped`.

- [ ] **Step 1: Write fixtures** — each the smallest project where go-to-definition has a target: a function defined in one place and called in another within the same file (Java fixture has no build file; jdtls handles it as a standalone file).
- [ ] **Step 2: Write `check.lua` runner** — runs on `VimEnter` + `vim.defer_fn`, triggers `User VeryLazy`, then runs global checks, then per-language checks; each language: `:edit` fixture, assert `vim.treesitter.highlighter.active[buf]`, then if `vim.fn.executable(exe)==1` wait up to `timeout_ms` (default 20000, jdtls 90000) for a client named `server`, then `vim.lsp.buf_request_sync(buf,'textDocument/definition',…)` at the call site returns ≥1 location; else SKIP. Ends with `cquit` code = failures.
  - Initial global checks: `no_error_messages`, `keymaps_have_desc` (every `check.recorded` entry has `desc`), `no_prefix_clashes` (per mode, no recorded lhs is a strict prefix of any other mapping's lhs from `nvim_get_keymap`/`nvim_buf_get_keymap`, comparing `vim.keycode` forms), `no_shadowing` (no recorded buffer-local lhs equals a recorded global lhs).
  - Optional real project: if env `CHECK_JAVA_PROJECT` is set, also open the first `*.java` under it with timeout 180000.
- [ ] **Step 3: Run baseline** — `./tests/check.sh`. Expected FAILs today: `keymaps_have_desc`, `no_prefix_clashes`, `no_shadowing`; Rust LSP SKIP/FAIL (broken proxy). Paste the output into the commit message body as the baseline.
- [ ] **Step 4: Commit** — `test: headless check harness and language fixtures`.

### Task 2: Modular layout (dissolve `cfg/`, one job per file)

**Files:**
- Create: `lua/czernous/options.lua`, `lua/czernous/keymaps.lua`, `lua/czernous/plugins/{ui,editor,git,search,completion,diagnostics}.lua`
- Modify: `lua/czernous/init.lua`, `lua/czernous/lazy.lua` (drop `require('czernous.cfg')`), `lua/czernous/plugins/{treesitter,lsp}.lua`
- Delete: `lua/czernous/cfg/`, `set.lua`, `remap.lua`, `theme.lua` contents move later (keep file, Task 6 rewrites), `plugins/{autocompletion,fugitive,harpoon,lualine,misc,telescope,theming,trouble,undotree,which-key}.lua`, `.luarc.json`

**Interfaces:**
- Consumes: Task 1 `check.global`.
- Produces: module names in File Structure above, and the keymap registry (owner: keymaps are messy/duplicated/hard to manage → one file):
  - `lua/czernous/keymaps.lua` returns `M` with groups `M.groups = { {name='Files & search', keys={…}}, {name='LSP', …}, {name='Git', …}, {name='Editing', …}, {name='Navigation', …}, {name='Toggles', …} }`; each key `{ mode, lhs, rhs, desc, plugin? }` where `rhs` is a string or function and `plugin` names the lazy.nvim plugin it needs.
  - `M.setup()` sets every key with no `plugin`.
  - `M.lazy(plugin) -> LazyKeysSpec[]` — used as `keys = require('czernous.keymaps').lazy('telescope.nvim')` in plugin specs, so plugin keys stay in the registry yet lazy-load the plugin.
  - `M.lsp(bufnr)` and `M.gitsigns(bufnr)` set the buffer-local groups (called from LspAttach / gitsigns `on_attach`).
  - `M.all() -> {mode,lhs,desc,group}[]` — used by the check's `--keymaps` table and which-key groups. `lua/czernous/lsp.lua` is created here holding the old `lsp-config.lua` contents unchanged (Task 3 rewrites it), required from `init.lua` after `lazy`.

- [ ] **Step 1: Add failing checks** — `keymaps_central` (every entry in `check.recorded` has `src` ending in `lua/czernous/keymaps.lua`); `duplicate_actions_report` (non-failing: prints groups of keys whose rhs is the same string/function, for the owner to choose — e.g. `<C-p>` & `<leader>pf`; also fails on the same mode+lhs registered twice); `no_cfg_dir` (`lua/czernous/cfg` absent); `plugin_specs_have_no_side_effects`: for each `lua/czernous/plugins/*.lua`, `dofile` it and assert `nvim_get_keymap` for n/x/o/v/i is unchanged and the return value is a table.
- [ ] **Step 2: Run** `./tests/check.sh` → both FAIL.
- [ ] **Step 3: Move code** — each `cfg/*-config.lua` body becomes the `config`/`opts` of its plugin spec; top-level `vim.keymap.set` in spec files becomes `keys = {…}` entries (with `desc`); merge duplicates (single which-key, single devicons, mason set up once). Remove dead code: `telescope_live_grep_open_files`, unused `telescope-ui-select` dependency on harpoon. Behaviour otherwise identical — do not change keys here.
- [ ] **Step 4: Run** `./tests/check.sh` → new checks PASS; no new FAILs vs baseline.
- [ ] **Step 5: Commit** — `refactor: one job per file, single keymap registry`.
- [ ] **Step 6: Owner checkpoint** — show the duplicate-actions report; owner picks which duplicates to drop (applied in Task 5).

### Task 3: LSP from `$PATH`, Mason as fallback, per-server overrides

**Files:**
- Modify: `lua/czernous/lsp.lua`, `lua/czernous/plugins/lsp.lua`
- Create: `after/lsp/rust_analyzer.lua`, `after/lsp/lua_ls.lua`, `after/lsp/jdtls.lua`

**Interfaces:**
- Produces in `lua/czernous/lsp.lua`:
  - `M.servers = { 'gopls', 'rust_analyzer', 'lua_ls', 'jdtls', 'csharp_ls', 'vtsls' }` (adding a language = one entry).
  - `M.setup()` — sets `'*'` capabilities from `cmp_nvim_lsp`, then for each server: `local cfg = vim.lsp.config[name]`; enable iff `cfg and cfg.cmd and type(cfg.cmd)=='table' and vim.fn.executable(cfg.cmd[1])==1` (function `cmd`s: enable unconditionally). Returns list of enabled names (used by the check).
  - LspAttach keymaps (moved from old file; Task 5 renames clashing ones).
- Mason: `opts = { PATH = 'append' }`, loaded before `M.setup()` so its bin dir is on PATH; no `ensure_installed`; delete `mason-lspconfig`.
- `after/lsp/rust_analyzer.lua`: returns the existing `procMacro.ignored` settings; adds `rustfmt.overrideCommand = { 'leptosfmt', '--stdin', '--rustfmt' }` **only if** `vim.fn.executable('leptosfmt') == 1`.
- `after/lsp/jdtls.lua`: data/workspace dir `stdpath('cache')/jdtls/<sanitised root path>`; if `vim.env.JAVA_HOME` is set, add `settings.java.configuration.runtimes = {{ name = 'JavaSE-<major from release file>', path = JAVA_HOME, default = true }}`; else nothing (jdtls uses PATH `java`). No literal paths.
- Broken servers: set `vim.lsp.config('*', { on_exit = … })`-level guard or use `vim.lsp.log` level so a server that exits with non-zero code during init produces one `vim.notify(…, WARN)` per server per session, not an ERROR.

- [ ] **Step 1: Add failing checks**
  - `mason_is_fallback_only`: `package.loaded['mason-lspconfig'] == nil`; PATH ends with Mason's bin dir rather than starting with it.
  - `enabled_matches_path`: `require('czernous.lsp').setup()` result equals exactly the servers whose `cmd[1]` is executable.
  - `leptosfmt_conditional`: `vim.lsp.config.rust_analyzer.settings['rust-analyzer'].rustfmt` is nil when `leptosfmt` not executable (current machine).
  - `jdtls_no_hardcoded_runtime`: with `JAVA_HOME` unset, `vim.lsp.config.jdtls.settings.java.configuration` has no `runtimes`; grep of `after/` and `lua/` finds no `/usr/lib/jvm` or `.sdkman`.
  - `broken_server_is_quiet`: prepend a temp dir to PATH containing an executable `fake-ls` (`#!/bin/sh\nexit 1`), `vim.lsp.config('fake_ls',{cmd={'fake-ls'},filetypes={'text'}})`, enable, open a `.txt`; after 3s: zero ERROR messages, ≤1 WARN.
  - `rootless_file_is_quiet`: `:edit` a fresh `go` file in a temp dir with no `go.mod`; no errors after 5s.
- [ ] **Step 2: Run** → these FAIL.
- [ ] **Step 3: Implement** as specified in Interfaces.
- [ ] **Step 4: Run** → PASS. Language results on this machine: Go and Lua PASS (Mason copies), Java PASS (Mason jdtls), Rust SKIP/WARN until `rustup component add rust-analyzer`, C# SKIP unless `csharp-ls` installed, TS SKIP. Then run once with `CHECK_JAVA_PROJECT=~/development/ristretto`; record result in commit body (a Gradle/JDK-27 toolchain failure is an environment issue — note it, don't work around it in config).
- [ ] **Step 5: Commit** — `feat(lsp): enable servers found on PATH; mason as fallback; per-server overrides`.

### Task 4: Treesitter parsers for any language

**Files:**
- Modify: `lua/czernous/plugins/treesitter.lua`

**Interfaces:**
- Produces: `ensure_installed` adds `gomod`, `java`, `c_sharp`, `javascript`, `typescript`, `tsx` (keep existing list). FileType autocmd: if `vim.treesitter.language.get_lang(ft)` has no installed parser, it is in `require('nvim-treesitter').get_available()`, and `vim.fn.executable('tree-sitter')==1`, call `install(lang)` then `vim.treesitter.start` on completion (`:wait()` not on the main path — use the async callback); otherwise do nothing.

- [ ] **Step 1: Add failing checks** — `parsers_installed` (each language listed above in `get_installed()`); `auto_install_on_open` (stub `require('nvim-treesitter').install` to record calls, set ft to an available-but-uninstalled lang, assert one call); `no_cli_no_install` (same, with PATH stripped of `tree-sitter`: zero calls, zero errors).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `feat(treesitter): parsers for all owner languages, install on first open`.

### Task 5: Keymaps — descriptions, no clashes, diagnostics, format, source

**Files:**
- Modify: `lua/czernous/keymaps.lua` (all key changes happen here only), `lua/czernous/options.lua`, `lua/czernous/lsp.lua`, `lua/czernous/plugins/ui.lua` (which-key groups derived from `M.groups`)

**Interfaces:**
- Produces in `lua/czernous/lsp.lua`: `M.format()` — if any client attached to the buffer supports `textDocument/formatting`, `vim.lsp.buf.format()`; else `vim.cmd('Neoformat')`. Bound to `<leader>f` (`desc = 'Format buffer'`).
- Key decisions (my calls, spec "keymap rules"):
  - `<C-k>`/`<C-j>` stay global quickfix next/prev; drop the normal-mode LSP `<C-k>` signature help (use built-in insert `<C-s>`; keep insert `<C-h>` alias).
  - LSP: keep built-ins `grn gra grr gri gO`; kickstart aliases `gd gr gI gD <leader>rn <leader>ca` kept only if clash-free; `<leader>ds`→`gO` (built-in), `<leader>ws`→`<leader>lw`, `<leader>D`→`<leader>lt`, `<leader>wa/wr/wl`→`<leader>lwa/lwr/lwl` — builder may adjust under the rules.
  - `<leader>d` (`"_d`) stays; `<leader>swn/swp`→`<leader>cn/<leader>cp` (swap parameter); `<leader>fb/fh`→`<leader>pb/<leader>ph` (keeps `<leader>p*` = project/find family) — `<leader>f` stays format.
  - `tgR`→`<leader>ttr`.
  - `<leader><leader>` acts only when `&ft` is `lua` or `vim`, else `vim.notify('Nothing to source for '..ft, WARN)`.
  - which-key groups: only groups that have ≥1 mapping (derive from final keys).
- Options: `vim.diagnostic.config({ signs = false, virtual_text = false, severity_sort = true, float = { border = 'rounded', source = true } })`; `signcolumn = 'yes'` (for gitsigns). No virtual text — owner's performance preference.

- [ ] **Step 1: Add failing checks** — `diagnostics_findable` (`virtual_text` is false, `severity_sort` true; lualine config includes the `diagnostics` component; `]d` in the Go fixture with an injected diagnostic opens a float window); `signcolumn_fixed`; `format_falls_back` (in a buffer with no LSP and stubbed `Neoformat` command, `M.format()` calls it); `source_only_lua_vim` (`<leader><leader>` in a `go` buffer → no error, one WARN); `which_key_groups_used` (every group prefix registered with which-key has ≥1 recorded mapping under it). Existing `keymaps_have_desc`, `no_prefix_clashes`, `no_shadowing` must turn green here.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → all keymap/diagnostic checks PASS.
- [ ] **Step 5: Commit** — `fix(keymaps): describe every key, remove clashes, visible diagnostics, one format key`.

### Task 6: Theme module with transparency

**Files:**
- Modify: `lua/czernous/theme.lua`, `lua/czernous/plugins/ui.lua`

**Interfaces:**
- Produces in `lua/czernous/theme.lua`:
  - `M.opts = { colorscheme = 'onedark', transparent = true }` — the single theme spot (Stylix will set these in stage 3).
  - `M.setup()` — creates a `ColorScheme` autocmd (augroup `czernous_theme`) that, when `M.opts.transparent`, sets `bg = 'NONE'` on editor-area groups (`Normal NormalNC SignColumn EndOfBuffer LineNr CursorLineNr FoldColumn StatusLine StatusLineNC WinBar WinBarNC TabLineFill` — builder may extend), preserving each group's other attributes (read with `nvim_get_hl(0,{name=…, link=false})`, rewrite with bg removed). Float groups (`NormalFloat FloatBorder Pmenu TelescopeNormal WhichKeyNormal`) are left untouched. Then applies `M.opts.colorscheme`.
  - `M.toggle_transparency()` — flips the flag and re-applies the current colorscheme. Keymap `<leader>tT`, `desc = 'Toggle transparent background'` (builder may pick another clash-free key).
- onedark spec: `style = 'warm'` unchanged.

- [ ] **Step 1: Add failing checks** — `transparent_normal` (`nvim_get_hl(0,{name='Normal'}).bg == nil` and `.fg ~= nil`); `floats_keep_bg` (`NormalFloat` has bg, either own or via link); `survives_colorscheme_change` (`:colorscheme catppuccin` → Normal bg nil); `toggle_restores_bg` (after toggle, Normal bg non-nil; toggle back → nil); `special_buffers_are_quiet` (open `:help`, `:Ex`, `:terminal`, `:enew` in turn; no errors).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `feat(theme): single theme spot with terminal transparency`.

### Task 7: Update plugins, README, final verification

**Files:**
- Modify: `lazy-lock.json`, `README.md`

- [ ] **Step 1: Update plugins** — `nvim --headless "+Lazy! update" +qa`; then `./tests/check.sh` → all PASS/SKIP as in Task 3 Step 4. If an update breaks a check, pin that plugin's previous commit in the lockfile and note it.
- [ ] **Step 2: README** — sections: "Layout" (File Structure table, one line per file), "Adding a language" (one entry in `M.servers` + optional `after/lsp/<name>.lua`; tools come from PATH/devshell, `:MasonInstall` as fallback), "Language versions" (chosen by the environment: devshell, `global.json`, `rust-toolchain.toml`, `JAVA_HOME`; one Neovim per project), "Machine setup" (clipboard tool per OS incl. `win32yank.exe` on WSL; `rustup component add rust-analyzer`; `dotnet tool install -g csharp-ls`), "Running the check" (`./tests/check.sh`, `CHECK_JAVA_PROJECT=…`), "Keymaps" (paste output of `./tests/check.sh --keymaps`, grouped by file), "Changed keys" (old → new table from Task 5).
- [ ] **Step 3: Verify** — `./tests/check.sh` full output and `CHECK_JAVA_PROJECT=~/development/ristretto ./tests/check.sh`; `nvim --headless --startuptime /tmp/st.txt +qa` and compare total with the baseline (must not be slower by >10%).
- [ ] **Step 4: Commit** — `chore: update plugins, document layout, keymaps and machine setup`.
