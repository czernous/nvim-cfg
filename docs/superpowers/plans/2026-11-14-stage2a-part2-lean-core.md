# Stage 2a Part 2 — Lean Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the owner-approved audit verdicts so the live config launches in ≤ 15 ms, with 22 plugins loaded on first use, blink.cmp completion, a base16/transparent theme, a built-in statusline, and the critique fixes.

**Architecture:** lazy.nvim stays (ADR 0001) with `defaults.lazy = true`; each plugin spec names its trigger. Theme = `mini.base16` fed by a palette data file, polarity following `'background'`, transparency by one rule over all highlight groups. Statusline is a ~60-line module, Lua parts cached and refreshed by events. Formatting goes through conform.nvim with the Spotless and jdtls rules kept in `format.lua`.

**Tech Stack:** Neovim 0.12.4, lazy.nvim, blink.cmp (Lua fuzzy), mini.base16, conform.nvim.

**Spec:** `docs/superpowers/specs/2026-11-14-stage2a-lean-core-design.md` · **Decisions:** `docs/perf/audit.md` §4–6, `docs/adr/0001-plugin-manager.md`

## Global Constraints

- Launch ≤ 15 ms wall clock on this machine (`tests/bench.sh`, fastest of 10; bare Neovim ≈ 9 ms). No measure slower than `docs/perf/baseline.md`.
- At startup only the theme plugin and lazy.nvim are loaded; everything else loads on first use.
- No plugin with a build or download step; external tools come from `$PATH`; a missing tool → one warning + fallback, never an error.
- No blocking calls at startup or on hot paths; no globals; no reflection; no deprecated APIs; no per-buffer state that outlives its buffer (existing checks + tripwires stay green).
- No OS/machine-specific code, no hard-coded SDK versions or paths.
- Keys keep their meaning; every changed/removed key is appended to `docs/perf/changed-keys.md` (old → new → why).
- Every new behaviour gets a check that is seen failing first; every new *rule* check gets a tripwire.
- `./tests/check.sh` and `./tests/check.sh --tripwires` green at the end of every task; commits use `-c user.name='Anton Chernous' -c user.email=czernous_a@hotmail.com` and the trailer `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.

## Review Focus

1. **First use of a lazily loaded plugin from an unusual entry point** (e.g. `:Telescope` typed as a command, `nvim file` given on the command line, a key pressed in the first 50 ms) → loads and works, no "module not found". Pinned in Task 1 (`lazy_entry_points`).
2. **Light terminal / background switch at runtime** → palette of the matching polarity is applied; a wrong-polarity palette is refused with a clear message. Pinned in Task 3.
3. **Selection visibility under transparency** (completion menu selected item, Visual, CursorLine, search) → still has a background. Pinned in Task 3 (`accents_keep_background`).
4. **Statusline in special buffers** (netrw, help, terminal, Telescope prompt, empty buffer) → renders, no error, no git/diagnostic lookups on dead buffers. Pinned in Task 4.
5. **Java project without an Eclipse formatter file / without jdtls** → `<leader>f` falls back (LSP defaults or warning), `<leader>F` only acts in Spotless projects. Pinned in Task 5.

---

### Task 1: Load everything on first use

**Files:** Modify `lua/czernous/lazy.lua`, `lua/czernous/init.lua`, `lua/czernous/lsp.lua`, all `lua/czernous/plugins/*.lua`, `tests/check.lua`

**Interfaces:**
- `lazy.lua`: `defaults = { lazy = true }`; `performance.rtp.disabled_plugins = { 'gzip','tarPlugin','tohtml','tutor','zipPlugin','rplugin','spellfile','osc52' }`; plugin root from `vim.env.NVIM_PLUGIN_ROOT` when set (then `install.missing = false`, lockfile under `stdpath('state')`).
- Triggers: theme `lazy=false, priority=1000`; statusline/which-key `event='VeryLazy'`; telescope `cmd='Telescope'` (+ loaded by `require` from keymaps); harpoon via `require`; treesitter(+textobjects, context), gitsigns, sleuth, lspconfig(+fidget) `event={'BufReadPre','BufNewFile'}`; completion `event='InsertEnter'`; fugitive `cmd={'Git','G','Gdiffsplit','Gvdiffsplit','Gread','Gwrite','Gedit'}`; mason `cmd={'Mason','MasonInstall','MasonUninstall','MasonUpdate','MasonLog'}`; neoformat `cmd` (until Task 5); lazydev `ft='lua'`.
- `lsp.lua`: `M.setup()` is called from `init.lua` on `VimEnter` via `vim.schedule` (after the first screen); completion capabilities are **not** requested from the completion plugin at startup (Task 2 supplies them without loading it).

- [ ] **Step 1: Failing checks** — `only_theme_loads_at_startup` (in a child Neovim: lazy.nvim's loaded set right at `VimEnter` ⊆ {lazy.nvim, theme plugin}); `launch_within_budget` (child launches ×7: fastest config launch − fastest bare launch ≤ 12 ms — generous ceiling against the ~5 ms target, to catch regressions without flaking); `lazy_entry_points` (child: `nvim +'Telescope find_files'` opens a picker; `nvim file.go` gets treesitter + LSP; `:Git` exists and loads fugitive; pressing `<leader>pf` immediately after `VimEnter` works). Tripwire `tripwire_eager.lua` (requires `telescope` at startup) must fail `only_theme_loads_at_startup`.
- [ ] **Step 2: Run** → the two startup checks FAIL (27 plugins at startup, ~70 ms).
- [ ] **Step 3: Implement** triggers and deferral as above.
- [ ] **Step 4: Run** `./tests/check.sh`, `--tripwires` → PASS; `./tests/bench.sh --label part2-task1` → launch ≤ 16 ms.
- [ ] **Step 5: Commit** — `perf: load every plugin on first use`.

### Task 2: blink.cmp replaces nvim-cmp

**Files:** Modify `lua/czernous/plugins/completion.lua`, `lua/czernous/lsp.lua`, `lazy-lock.json`, `tests/check.lua`, `tests/bench.lua` (adapter already knows blink)

**Interfaces:**
- Spec: `'saghen/blink.cmp'`, `version = '*'`, `event = 'InsertEnter'`, dependency `rafamadriz/friendly-snippets`; `fuzzy.implementation = 'lua'` (no binary); sources `lsp, path, snippets`; snippets through built-in `vim.snippet`; documentation window auto-shown; bordered, follows theme.
- Keys (same as today): `<C-n>/<C-p>` select, `<C-b>/<C-f>` scroll docs, `<C-Space>` open, `<CR>` accept, `<Tab>/<S-Tab>` next/previous item else jump in snippet else fallback.
- Capabilities: `lsp.lua` sets `'*'` capabilities from a static table equal to what blink advertises (snippet support, resolve support, etc.) so blink is **not** loaded before insert mode; a check asserts the static table deep-equals `require('blink.cmp').get_lsp_capabilities()` (so an upstream change is detected).
- Removed: nvim-cmp, LuaSnip, cmp_luasnip, cmp-nvim-lsp, cmp-path.

- [ ] **Step 1: Failing checks** — `completion_menu_appears` (pty child, as in `bench.lua`: type `pri` in the Lua fixture → menu visible within 500 ms, first item accepted with `<CR>` inserts `print`); `completion_capabilities_current` (static table == blink's); `no_removed_plugins` (lockfile has none of the five removed names).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** checks + `bench.sh --label part2-task2` → completion ≤ 15 ms (baseline ~75 ms).
- [ ] **Step 5: Commit** — `feat(completion): blink.cmp (pure Lua) replaces nvim-cmp stack`.

### Task 3: base16 palettes, polarity, rule-based transparency

**Files:** Rewrite `lua/czernous/theme.lua`; create `palettes/*.json`; modify `lua/czernous/plugins/ui.lua`, `lua/czernous/options.lua` (`winborder = 'rounded'`), `tests/check.lua`

**Interfaces:**
- Palette file = plain data any config can read: `{ "name": "...", "variant": "dark"|"light", "base00".."base0F": "#rrggbb" }`. Shipped: `onedark` (default dark), `one-light` (default light), plus `gruvbox-dark`, `catppuccin-mocha`, `gruvbox-light`, `catppuccin-latte`.
- `theme.opts = { dark = 'onedark', light = 'one-light', transparent = true }`; palette source override: `vim.env.NVIM_BASE16_PALETTE` (path to a palette file — how Stylix will supply it).
- `theme.setup()` applies the palette matching `vim.o.background` via `require('mini.base16').setup({ palette = … })`, then the transparency rule; `OptionSet background` re-applies for the new polarity.
- `theme.use(name)` switches palette; refuses (WARN, no change) if `variant ~= vim.o.background`.
- Transparency rule: for every group in `nvim_get_hl(0, {})` whose `bg` equals the palette's `base00` or `base01`, clear `bg`. Accents (`Visual`, `CursorLine`, `PmenuSel`, `Search`, `IncSearch`, `CurSearch`, diff groups) must end with a background: if the palette gave one of them `base00/01`, they are set to `base02`.
- `theme.toggle_transparency()` stays on `<leader>tT`.
- Removed: onedark.nvim, catppuccin.

- [ ] **Step 1: Failing checks** — `palette_files_valid` (each JSON has 16 colours + variant); `polarity_follows_background` (`set background=light` → active palette variant light; `theme.use('onedark')` then warns and keeps the light palette); `ui_is_transparent` (with transparency on: `Normal`, `NormalFloat`, `Pmenu`, `FloatBorder`, `TelescopeNormal`, `WhichKeyNormal`, `StatusLine` have no bg — and no group at all has bg ∈ {base00, base01}); `accents_keep_background` (the accent list above each has a bg); `external_palette_used` (`NVIM_BASE16_PALETTE` → that palette's base08 appears in `Error`-family fg); existing `toggle_restores_bg` adapted. Tripwire `tripwire_opaque.lua` (sets a group's bg to base00 after theme load via `ColorScheme`-free direct call) must fail `ui_is_transparent`.
- [ ] **Step 2–4:** RED → implement → GREEN; `bench.sh --label part2-task3` launch ≤ 16 ms.
- [ ] **Step 5: Commit** — `feat(theme): base16 palettes, polarity follows terminal, one-rule transparency`.

### Task 4: Built-in statusline replaces lualine

**Files:** Create `lua/czernous/statusline.lua`; modify `lua/czernous/plugins/ui.lua` (remove lualine), `lua/czernous/init.lua`, `tests/check.lua`

**Interfaces:**
- Layout: ` MODE  path/file.ext [+]   branch   E2 W1` … `filetype   line:col ` — minimal, palette colours, no separators/powerline glyphs.
- `vim.o.statusline` uses built-in items for file (`%f %m`), position (`%l:%c`) and filetype (`%Y`→ lowercased via cached Lua); Lua parts (mode label, branch from `vim.b.gitsigns_head`, diagnostic counts) are cached strings recomputed only on `ModeChanged`, `DiagnosticChanged`, `BufEnter`, `User GitSignsUpdate` — cursor movement runs no Lua.
- `statusline.setup()` called after first screen (`VeryLazy`).
- nvim-web-devicons stays only as an optional dependency of Telescope.

- [ ] **Step 1: Failing checks** — `statusline_native` (lualine not in lockfile; `vim.o.statusline` set; rendered text contains mode, file name, `line:col`); `statusline_shows_diagnostics_and_branch` (inject 2 errors + set `vim.b.gitsigns_head` → rendered text has `E2` and the branch); `statusline_special_buffers` (help, netrw, terminal, empty buffer render without error); `statusline_allocation_budget` (1000 `CursorMoved` events with only our statusline autocmds → 0 bytes from our augroup; 1000 statusline evaluations ≤ 200 B each). Tripwire `tripwire_statusline_alloc.lua` (adds a `CursorMoved` handler in our augroup that builds a table) must fail the budget check.
- [ ] **Step 2–4:** RED → implement → GREEN; bench: `alloc CursorMoved` drops by ~1.6 KB vs baseline.
- [ ] **Step 5: Commit** — `feat(ui): built-in statusline replaces lualine`.

### Task 5: Formatting — conform.nvim, instant Java, exact Spotless on demand

**Files:** Modify `lua/czernous/format.lua`, `lua/czernous/plugins/editor.lua`, `after/lsp/jdtls.lua`, `lua/czernous/keymaps.lua`, `tests/check.lua`

**Interfaces:**
- conform.nvim (`cmd='ConformInfo'`, loaded by `require` from `format.lua`): `formatters_by_ft = { lua={'stylua'}, javascript/typescript/tsx/json = {'biome','prettier', stop_after_first=true} }`, `lsp_format='fallback'`; formatters absent from `$PATH` are skipped by conform itself.
- `<leader>f` → `format.format()`: conform (project/CLI formatter, else LSP). For Java, LSP = jdtls using the project's Eclipse formatter profile.
- `<leader>F` → `format.spotless()`: the existing Spotless IDE-hook path (async, exact); WARN "not a Spotless project" elsewhere.
- `after/lsp/jdtls.lua`: `settings.java.format.settings.url` = the project's Eclipse formatter file, found at server start (root known in `before_init`/`root_dir` callback) by: (1) a path inside `eclipse().configFile(...)` / `configFile("…")` in the root or module Gradle build files; else (2) first of `config/eclipse-formatter.xml`, `eclipse-formatter.xml`, `.settings/formatter.xml`, `config/formatter.xml`; else unset (jdtls defaults).
- Removed: neoformat; `:Format` buffer command = `format.format`.

- [ ] **Step 1: Failing checks** — `format_uses_conform_then_lsp` (fake `stylua` on PATH is invoked for a Lua buffer; without it and with an LSP formatter stub, LSP is used; with neither, one WARN); `spotless_on_capital_f` (fake Spotless project: `<leader>F` transforms the buffer, `<leader>f` does not call gradlew); `spotless_key_outside_project_warns`; `jdtls_formatter_profile_found` (fake Gradle root with `eclipse().configFile(rootProject.file("config/fmt.xml"))` → resolver returns that path; conventional-path fallback; none → nil). Existing Spotless checks retargeted at `format.spotless()`.
- [ ] **Step 2–4:** RED → implement → GREEN; manual verification on the Java fixture only (never against the owner's live project): jdtls picks up a fixture profile.
- [ ] **Step 5: Commit** — `feat(format): conform.nvim; instant Java formatting with project profile; Spotless on <leader>F`.

### Task 6: Drops, built-ins, options, keymap fixes

**Files:** Modify `lua/czernous/plugins/{search,git,editor,diagnostics}.lua` (delete `diagnostics.lua`), delete `lua/czernous/incremental_selection.lua`, modify `lua/czernous/keymaps.lua`, `lua/czernous/options.lua`, `tests/check.lua`; create `docs/perf/changed-keys.md`

**Interfaces:**
- Dropped plugins: telescope-fzf-native, vim-rhubarb, undotree (→ `packadd nvim.undotree` + `:Undotree` on `<leader>u`), trouble.nvim.
- Selection: `<C-space>` (normal) = `van`; (visual) = `an`; `<M-space>` (visual) = `in` — thin aliases to the built-ins; module deleted.
- Options: remove `guicursor=""` and `smartindent`; add `undofile`, `ignorecase`, `smartcase`, `scrolloff=8`, `splitright`, `splitbelow`, `inccommand='split'`, `cursorline`, `confirm`; `vim.g.netrw_banner = 0`; diagnostics popup after jump via `vim.diagnostic.config({ jump = { on_jump = … } })`.
- Keys: `<leader>y`, `<leader>d` also in visual mode; remove `Y`, `<C-k>/<C-j>` quickfix, `<leader>k/<leader>j`, `<leader>vd`, `[d`/`]d` remaps, `<leader>wa/wr/wl`, Trouble keys; LSP primary keys = built-ins `grn gra grr gri grt gO` with which-key labels (`grr`, `gO` keep the Telescope pickers); keep aliases `<leader>ca`, `<leader>rn`, `gd`, `gD`, `K`; add interim `<leader>pd` = Telescope diagnostics (project) until 2b's Problems group; `<leader>td` desc corrected.
- Registry groups renamed to match which-key prefixes one-to-one.

- [ ] **Step 1: Failing checks** — `dropped_plugins_gone` (lockfile); `builtin_undotree_key`; `node_selection_aliases` (`<C-space>` twice in the Lua fixture grows the selection — existing test retargeted; no `czernous.incremental_selection` module); `options_set` (each option above); `clipboard_keys_in_visual`; `removed_keys_gone` + `builtin_lsp_keys_labelled` (which-key has descriptions for the `gr` family); `diagnostic_popup_on_jump` (built-in `]d` opens a float); `netrw_no_banner`.
- [ ] **Step 2–4:** RED → implement → GREEN (existing `owner_key_choices`, `no_prefix_clashes`, `no_shadowing`, `keymaps_central` stay green).
- [ ] **Step 5: Commit** — `refactor: drop replaced plugins, use built-ins, fix options and keymaps`.

### Task 7: `:checkhealth czernous`

**Files:** Create `lua/czernous/health.lua`; modify `tests/check.lua`

**Interfaces:** `:checkhealth czernous` reports, per external tool, found/missing and what depends on it: required — `git`, C compiler (`cc`/`gcc`/`clang`), `tree-sitter`, `rg`, `fd`; per language — each program in `lsp.servers`; optional — clipboard provider (`vim.fn.has('clipboard')`), `stylua`, `biome`/`prettier`, `leptosfmt`, `make`-free note. Missing required = ERROR with a one-line "install the `<name>` package" hint (no distro-specific commands); optional = WARN. Runs only on demand (blocking lookups are fine there; allowlisted with that reason).

- [ ] **Step 1: Failing check** — `health_lists_tools` (run with a PATH lacking `rg`: output has an ERROR line naming ripgrep and an OK line for git; no Lua errors). **Step 2–4:** RED → implement → GREEN.
- [ ] **Step 5: Commit** — `feat: :checkhealth czernous lists required system tools`.

### Task 8: Final numbers and owner test

- [ ] **Step 1:** `./tests/bench.sh --runs 12 --label part2-final` twice; write `docs/perf/results.md` (baseline vs final table, only stable numbers, spreads quoted).
- [ ] **Step 2:** `./tests/check.sh`, `--tripwires`, `CHECK_CANARY=1` all behave; `git status` clean after a run.
- [ ] **Step 3:** Hand the owner: results table, `docs/perf/changed-keys.md`, what to try. Commit — `docs: stage 2a results`.
