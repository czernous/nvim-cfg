# Stage 2a audit — plugins, performance, config critique

2026-11-14 · Neovim 0.12.4 · numbers from `tests/bench.sh` (fastest of 10 runs unless noted;
two passes agreeing within 15%) · baseline: `docs/perf/baseline.md` · nothing here has been
changed in the live config yet. **Each verdict needs the owner's yes/no.**

## 1. Headline

| | Launch (wall clock) | Notes |
|---|---|---|
| Bare Neovim, no config | 8.5–10 ms | the floor on this machine |
| Config today | 71–89 ms | 27 of 30 plugins load before the first screen |
| **Lean prototype** (same plugins, loaded on first use) | **13.9 ms** | sandbox; LSP, highlighting, lazy-loading verified working |

The owner's 15 ms target is reachable **by loading on demand alone** — no plugin has to be
given up for speed. Side effect: opening a Go file until highlighted went 114 → 42 ms,
Java 114 → 49 ms. (Before all this, the AppImage packaging cost a further ~75 ms per launch;
replaced with an unpacked build at `~/.local/bin/nvim`.)

## 2. Where startup time goes today

Per-plugin load time at startup (lazy.nvim profile), total ≈ 57 ms:

| Plugin | ms | Why it loads at startup |
|---|---|---|
| nvim-cmp (+ LuaSnip 2.5, sources) | 21.3 | LSP setup asks it for capabilities; snippets parsed eagerly |
| lualine | 5.8 | statusline |
| nvim-lspconfig | 5.4 | plus fidget 3.7, mason 1.5 as dependencies |
| telescope | 3.8 | not needed until a search key is pressed |
| harpoon | 3.6 | not needed until a harpoon key is pressed |
| onedark (colorscheme file) | 3.4 | needed for the first screen |
| lazy.nvim itself | 3.0 | |
| gitsigns 1.9, fugitive 1.4, treesitter 1.2, others < 0.5 | | only needed once a file is open |

## 3. Hot paths: memory allocated per event

Exact figures (bytes of Lua memory per event, GC stopped), attributed per plugin:

| Event (how often) | Who | Bytes/event |
|---|---|---|
| Cursor move in insert mode (every keystroke) | **nvim-cmp** | 13,535 |
| Cursor move, any mode | **lualine** (re-renders statusline each time) | 1,640 |
| Entering a buffer | lualine | 2,660 + 1,640 |
| Entering a buffer | which-key | 1,710 |
| Cursor move / scroll | treesitter-context | ~505 |
| Cursor move | matchparen (built-in) | ~160 |

With blink.cmp loaded the insert-mode figure is ~4,000 total; with no completion plugin ~1,600.

## 4. Verdicts

| # | Plugin | Verdict | Reason | Risk / cost |
|---|---|---|---|---|
| 1 | lazy.nvim | **Keep** (see ADR 0001) | built-in `vim.pack` measured no faster (14.1 vs 13.9 ms) and has no lazy-loading; ours would be ~80 lines to maintain (the quick spike version already broke completion triggering) | one env hook for Nix (`NVIM_PLUGIN_ROOT`), tested working offline from a read-only folder |
| 2 | nvim-cmp, LuaSnip, cmp_luasnip, cmp-nvim-lsp, cmp-path | **Replace with blink.cmp** (pure-Lua mode, no binary) | menu appears ~4 ms after a keystroke vs ~70–80 ms; 5 plugins → 1; 13.5 KB → ~2.4 KB per insert-mode cursor move; LuaSnip's regex helper needs a build step | Tab/Enter behaviour re-created; snippets via built-in `vim.snippet` + friendly-snippets |
| 2b | — alternative | built-in completion (`autocomplete`) | fastest (1–2 ms) and zero plugins, but plainer: no docs side-window, weaker snippets/fuzzy | owner's choice; recommendation is blink for the IDE feel |
| 3 | friendly-snippets | Keep | snippet collection used by blink | — |
| 4 | onedark, catppuccin | **Replace with a base16 palette** (`mini.base16`, 1 plugin) | owner wants Stylix-driven theming; launch unchanged (14.4 ms); catppuccin was never used | selection highlight must be checked under transparency (lost its background in the prototype) |
| 5 | lualine | Keep, load just after first screen | 5.8 ms off the launch path | re-renders on every cursor move (1.6 KB): fix by refreshing on mode/diagnostic/branch events only, or replace with a ~40-line native statusline in 2b |
| 6 | nvim-web-devicons | Keep (loaded by whoever needs icons) | — | — |
| 7 | which-key | Keep, load after first screen | essential for learning the keys | 1.7 KB per buffer enter; acceptable |
| 8 | telescope | Keep, load on first search key | 3.8 ms off launch | — |
| 9 | telescope-fzf-native | **Drop** | needs `make` + compiler at install (rule: no build steps); Telescope's Lua sorter is fine at this repo size | slower fuzzy-sort on very large repos; fzf-lua is the upgrade path but needs `fzf` installed (not on this machine, so not measured) |
| 10 | plenary | Keep (needed by telescope, harpoon) | — | — |
| 11 | harpoon | Keep, load on first harpoon key | owner uses it | — |
| 12 | undotree (plugin) | **Drop → built-in `nvim.undotree`** (ships with 0.12) | built-in first | slightly different look; same key `<leader>u` |
| 13 | vim-sleuth | Keep, load when a file opens | auto-detects indentation; no built-in equivalent | — |
| 14 | neoformat | **Replace with conform.nvim**, load on `<leader>f` | async, per-language formatter lists, picks project formatters; needed for JS/TS (Biome/Prettier) | Spotless-first rule stays (as a conform formatter); can't be end-to-end tested for JS here (no Node/Bun) |
| 15 | vim-fugitive | Keep, load on `:Git`/`<leader>gs` | owner uses it | — |
| 16 | vim-rhubarb | **Drop** unless you use `:GBrowse` (open file on GitHub) | no key points at it | — |
| 17 | gitsigns | Keep, load when a file opens | — | — |
| 18 | nvim-treesitter, textobjects | Keep, load when a file opens | parsers + text objects | — |
| 19 | treesitter-context | Keep for now, load when a file opens | sticky function header; 2b decides if you want it | ~500 B per cursor move |
| 20 | nvim-lspconfig | Keep, load when a file opens | only provides per-server defaults | — |
| 21 | mason | Keep, load on `:Mason*` | manual fallback installer | — |
| 22 | fidget | Keep until 2b | LSP progress messages; 2b redesigns LSP messages as floating windows | — |
| 23 | lazydev | Keep (Lua files only) | Neovim API completion when editing the config | — |
| 24 | trouble | **Drop** (already decided) | 2b's "Problems" keys replace it | — |
| — | `incremental_selection.lua` (our code) | **Delete → built-in `an` / `in`** | 0.12 has node selection built in: `van` selects, `an` again grows, `in` shrinks | `<C-space>` can stay as an alias for discoverability |

Result: 30 plugins → 22, none loaded before the first screen except the theme and the plugin manager.

**External tools the config relies on** (must be on `$PATH`; all present here except where
noted): git, a C compiler + `tree-sitter` CLI (parsers), ripgrep, fd, language servers per
language, `win32yank.exe` (WSL clipboard — missing), `leptosfmt` (optional — missing).
Proposed: a `:checkhealth czernous` section that lists each tool, found/missing, and what
stops working without it — this is what makes "pull the config on the Arch machine and it
works" checkable.

## 5. Config and keymap critique

### Options (`options.lua`)
- `guicursor = ""` forces a block cursor in every mode, so the cursor never tells you which
  mode you're in — unhelpful while learning. Propose the default (bar in insert, block in normal).
- Missing, and worth having: `undofile` (undo survives restarts), `ignorecase`+`smartcase`
  (search), `scrolloff = 8`, `splitright`/`splitbelow`, `inccommand = "split"` (live preview
  for `<leader>s`), `cursorline`, `confirm` (ask instead of failing on unsaved changes),
  `winborder = "rounded"` (one setting gives every popup a border — needed once popups are transparent).
- `smartindent` is redundant (treesitter indentation is on); `tabstop/shiftwidth = 4` are
  overridden per file by vim-sleuth — keep as fallback only.

### Keymaps (`keymaps.lua`)
Bugs / traps:
- `<leader>y` and `<leader>d` exist only in normal mode — the common case (select text, then
  copy to clipboard / delete without yanking) doesn't work. Add visual mode.
- `<C-k>` = *next* quickfix item and `<C-j>` = *previous*: backwards from j/k (down/up).
- `Y` → `yg$`: Neovim's default `Y` already yanks to end of line. Delete.
- `<leader>td` is labelled a toggle but only previews.

Duplicates of built-ins (teach the built-in, delete ours — works in any Neovim):
- `<C-k>/<C-j>` and `<leader>k/<leader>j` → built-in `]q` `[q` `]l` `[l`.
- `<leader>vd` → built-in `<C-w>d`; `[d`/`]d` → built-ins (configure the popup once via
  `vim.diagnostic.config({ jump = { on_jump = ... } })` instead of remapping).
- `<leader>rn`, `<leader>ca`, `gI`, `<leader>D` → built-in `grn`, `gra`, `gri`, `grt`
  (keep one set; propose the built-ins plus which-key labels for the `gr` family).
- `<C-space>`/`<M-space>` selection → built-in `an`/`in`.
- `<leader>wa/wr/wl` (workspace folders): rarely needed; propose removing.

Missing for an IDE-like feel (proposed for 2b, listed so you can veto early):
- window movement (`<C-h/j/k/l>`), next/previous buffer and close buffer, save;
- resume last search, search word under cursor, find keymaps (`<leader>pk`);
- a terminal toggle; git blame line toggle is there but hidden under `<leader>tb`.

Structure: the registry works; group names should match the which-key prefixes one-to-one
(today "Editing" mixes formatting, clipboard, undo, transparency).

### Lua / engineering
- Fixed already in this stage: per-buffer leak in selection code; deprecated
  `vim.diagnostic.jump({float=…})` (removed in 0.14) and `vim.loop`; a blocking PATH lookup
  on every startup; which-key consuming the shared prefix table.
- Still open: `lua/czernous/lsp.lua` asks the completion plugin for capabilities at startup
  (forces it to load) — compute lazily; Spotless formatting goes through a full Gradle
  invocation (~1 s warm, ~2 s cold, even when nothing changes).

### Java formatting speed (owner question)
The ~1 s is Gradle's start-up + configuration time, not Neovim's and not Spotless's
formatting itself. Options: (a) keep exactness, accept ~1 s, async (today); (b) make
`<leader>f` instant by giving jdtls the project's Eclipse formatter file (same formatter
Spotless uses) and run real Spotless only on demand / before commit; (c) both: instant
jdtls on `<leader>f`, Spotless on `<leader>F`. Recommendation: (c).

### Upstream quirk found
Neovim 0.12.4's LSP startup errors ("Invalid buffer id") if a buffer is wiped in the same
tick it was opened. Harmless in normal use; the leak check works around it.

## 6. Owner decisions

Owner checkpoint, 2026-11-14:

| Item | Decision |
|---|---|
| Completion engine | **blink.cmp** (pure-Lua mode) replaces nvim-cmp + LuaSnip + sources |
| Plugin manager | **Keep lazy.nvim** (ADR 0001 accepted) |
| Java formatting | **Instant + exact on demand**: `<leader>f` = jdtls with the project's Eclipse formatter file; `<leader>F` = real Spotless |
| All remaining verdicts and critique fixes | **Approved**: drop telescope-fzf-native, rhubarb, undotree plugin (→ built-in), our selection module (→ built-in `an`/`in`), Trouble; base16 theme; conform.nvim; load everything on demand; options and keymap fixes — owner tests afterwards and may veto; every key change is listed |
