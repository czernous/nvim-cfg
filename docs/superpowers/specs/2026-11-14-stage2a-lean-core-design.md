# Stage 2a — Lean, fast, robust core

Date: 2026-11-14 · Repo: `~/.config/nvim`, branch `step1-modular` (merged only when all
of stage 2 is done) · Neovim 0.12.4 · Builds on: `2026-11-14-step1-modular-working-config-design.md`

## Why

The owner wants an editor that works like an IDE but is much lighter and faster, and
that **doesn't break or need fiddling**. They enjoy Vim and Linux but not spending
hours configuring; they're still learning Vim and rely on Claude to know what Neovim can
do. Later, Nix devshells will provide per-stack environments and Neovim must work
seamlessly in any of them; scheduled update jobs (stage 2c) will keep everything on the
newest stable versions and only adopt updates that pass the checks.

Stage 2a creates the **baseline** all of that builds on: the smallest, fastest set of
plugins that does everything the owner needs, measured, and built so that future
updates and Nix packaging have as little as possible to go wrong.

## Stage 2 overview (for orientation; only 2a is designed here)

- **2a — lean, fast core** (this doc): plugin audit, replacements, lazy-loading, benchmarks.
- 2b — IDE feel and UI: "Problems" workflow (see errors, jump, fix with preview, lightbulb),
  LSP messages in floating windows, start screen with load time, UI polish.
- 2c — update jobs: GitHub Actions (plain Linux runner + NixOS image), newest stable
  Neovim + plugins tested in isolation, adopted only when green, otherwise a report of
  exactly what breaks and how to fix it. Designed in depth when we get there.
- 2d — learning aids + documentation (README, keymap guide).
- 3 — Nix.

## Goals

1. **Every plugin earns its place.** An audit gives each current plugin a verdict —
   keep / replace / drop — with the reason and its measured cost. The owner sees the
   audit and can veto any verdict **before** anything changes.
2. **Built-in first.** Where Neovim 0.12 does the job (commenting, LSP config,
   `vim.snippet`, `vim.lsp.completion`, `vim.pack`, `:Inspect`, etc.), the built-in is
   preferred unless a plugin is clearly better for the owner (ease of use counts:
   owner is not a Vim expert).
3. **No build or download steps on install.** Prefer pure-Lua plugins. No `make`,
   `cargo build`, or plugins that download binaries. External programs (ripgrep, fd,
   fzf, language servers, formatters, tree-sitter CLI) come from `$PATH` — a devshell or
   Nix provides them later. Where a plugin *optionally* uses a native component, use
   its pure-Lua mode.
4. **Load only what's needed.** Nothing that isn't needed to draw the first screen
   loads at startup; everything else loads on first use (key, command, filetype, event).
5. **Measured speed, with a regression guard.** A benchmark script measures, on this
   machine (median of ≥10 runs):
   - startup to first screen, no file (`--startuptime`, "NVIM STARTED");
   - opening each fixture file until treesitter highlighting is active;
   - time until completion items appear after typing in a fixture (LSP attached).
   Baseline numbers are recorded before any change; the final numbers are compared.
   **Targets (revised 2026-11-14 after measuring; owner: "we can do 15 ms on this machine"):**
   launch ≤ 15 ms wall clock on this machine with a non-AppImage Neovim (bare Neovim is
   ~9–11 ms, so the config may add only ~4–6 ms: everything not needed for the first
   screen loads after it); no individual measure slower than its baseline. Baseline:
   `docs/perf/baseline.md` (launch 89 ms min, config overhead ~79 ms; AppImage adds a
   further ~75 ms per launch — owner approved replacing it). Startup gets a check in `tests/check.sh` that fails above a
   generous ceiling (to catch big regressions like the 1 s one found in step 1, without
   being flaky).
6. **Ready for Nix and updates.** The chosen plugin manager must work both (a) on plain
   machines, fetching plugins from a lockfile, and (b) with plugins supplied by Nix
   (already on `packpath`), without changing the Lua config. Lockfile stays in the repo.
7. **Same behaviour for the owner.** All keys from step 1 keep working with the same
   meaning (except where the audit replaces a plugin — then the replacement provides the
   same action on the same key). Any unavoidable key change is listed for the owner.
8. **Step 1 leftovers fixed** (from the step 1 review backlog):
   - lualine theme follows the theme module (`'auto'`), not hard-coded `onedark`;
   - checks that can't fail are fixed (`direct_open_attaches` SKIPs without lua_ls;
     `which_key_groups_used` must be able to fail; `rootless_file_is_quiet` asserts
     highlighting; `no_prefix_clashes` checks both directions);
   - C# fixture doesn't hard-code a .NET version;
   - servers installed mid-session via `:MasonInstall` are picked up without restart,
     or the limitation is stated where `:MasonInstall` is suggested;
   - Spotless detection also finds Spotless applied in subprojects/convention plugins,
     and a non-executable `gradlew` gives a clear warning, not a raw error.

9. **Engineering standards on par with the owner's ristretto project**, translated to
   Lua/Neovim and **enforced by checks, not by review** (a rule a person has to remember
   eventually gets forgotten):
   - *Fitness checks* (in `tests/check.sh`), each proven by a deliberate tripwire that
     must make it fail ("break it and watch it fail before you believe it"):
     - no blocking calls at startup or on hot paths: `vim.fn.system`/`systemlist`,
       `vim.fn.executable`/`exepath`, `io.popen`, `os.execute`, `vim.system():wait()`
       outside explicitly allowed sites;
     - no global variables written by the config (`_G`, implicit globals);
     - no `debug.*` / string-built dynamic dispatch ("reflection") in config code
       (tests exempt);
     - module boundaries: plugin spec files only return specs; keys only in
       `keymaps.lua`; no deprecated APIs (`vim.loop`, deprecated `vim.lsp.*`).
   - *No leaks:* any state keyed by buffer/window/client is released when that
     buffer/window/client goes away (e.g. `incremental_selection.lua` keeps a
     per-buffer table that is never cleared today). A check opens and wipes ~100
     buffers and asserts Lua memory (`collectgarbage('count')` after a full collect)
     returns to within a small bound.
   - *Allocation is the instrument for hot paths:* anything running per keystroke /
     cursor move / redraw (autocmds on `CursorMoved`, `TextChanged*`, statusline
     functions, completion hooks) is measured as bytes allocated per event (Lua
     `collectgarbage('count')` delta over N events) — exact and load-independent — with a
     budget per hook. Throughput/latency numbers are reported with the spread of ≥2
     agreeing runs.
   - *Hot-path Lua style:* cache module lookups in locals, no closures/tables created
     per event, `vim.api` over `vim.fn` where equivalent, async (`vim.uv`, `vim.system`
     with callback) for any I/O.
   - *Why-comments and decision records:* decisions a reader could expect to go the
     other way (plugin choices, plugin manager, theme mechanism) get a short ADR in
     `docs/adr/`.
   - SIMD/native code: not applicable to config Lua (LuaJIT has no SIMD; the heavy work —
     tree-sitter parsing, fuzzy matching — is already native). Revisit only if a
     measurement shows a hot loop in our Lua.
10. **Themes: several base16 palettes, dark and light, following the terminal.**
   - A few curated palettes ship in the repo (e.g. One Dark plus 2–3 other dark and 2–3
     light ones); on Nix, Stylix supplies the palette instead.
   - **Polarity follows the system/terminal:** Neovim detects the terminal background
     (sets `'background'`); only palettes matching it can be active. A light palette can't
     be chosen while the terminal is dark and vice versa; if the terminal switches
     (`OptionSet background`), Neovim switches to the configured palette of the new polarity.
   - **Transparency applies to the whole UI** (owner, 2026-11-14: solid popups next to a
     transparent editor look wrong): floating windows, Telescope/picker, completion menu,
     hover, which-key are transparent too, kept readable by a visible border. Supersedes
     step 1's "popups keep a solid background".
   - **Rule-based, never a per-element list** (owner: "that should not be hardcoded"):
     after a palette is applied, every highlight group whose background is one of the
     palette's *background* colours (base16 `base00`/`base01`) loses its background —
     found by scanning all groups, not by naming plugins or elements. Accent backgrounds
     (selection, search, cursor line, diff) are other palette colours and stay. Groups
     plugins define later link to standard groups and inherit the result; a check opens
     the picker/completion/hover/which-key and asserts none paints a palette background.
   - 2a builds the palette mechanism + polarity rule; a theme picker UI is 2b.

## Decisions already made (owner)

- Editor stays **AI-free**: completion and fixes come from language tools only.
- **Trouble is dropped** (owner: it only shows lists they already have). In 2a its keys
  go away; the proper "Problems" workflow arrives in 2b. Interim: errors list via the
  picker (e.g. `:Telescope diagnostics` or the replacement picker), next/prev error via
  `]d`/`[d` — so nothing is lost meanwhile.
- No inline diagnostic text (performance), project-formatter-first formatting,
  search scoped to the current file's project, transparency, PATH-first tools,
  no OS/machine-specific code, no hard-coded SDK versions — all carry over from step 1.
- Newest **stable** Neovim is the target; nightly is only ever tested, not adopted (2c).

## Candidate verdicts (my proposals — the audit confirms or overturns them with measurements)

| Area | Today | Proposal | Why |
|---|---|---|---|
| Plugin manager | lazy.nvim | **decide by spike**: lazy.nvim vs built-in `vim.pack` (+ small lazy-load helper) | must lazy-load (goal 4) *and* accept Nix-supplied plugins (goal 6); `vim.pack` is built in (fewer moving parts) but has no lazy-loading |
| Completion | nvim-cmp + 4 sources + LuaSnip | blink.cmp (pure-Lua fuzzy mode) **or** built-in `vim.lsp.completion` | fewer plugins, faster; must keep snippets, path completion, LSP items |
| Snippets | LuaSnip + friendly-snippets | built-in `vim.snippet` + friendly-snippets via the completion plugin | LuaSnip's optional jsregexp needs a build step |
| Picker | Telescope + fzf-native (`make`) | fzf-lua (uses `fzf` from PATH) **or** Telescope without fzf-native | fzf-native needs a compiler; fzf-lua is faster on big repos |
| Formatting | Neoformat + our `format.lua` | conform.nvim (with our Spotless logic as a conform formatter) | async, per-filetype, project-aware; keeps owner's Spotless-first rule |
| Diagnostics list | Trouble | **drop** (owner decision) | — |
| Colorscheme | onedark + catppuccin | **base16 palette** rendered by one pure-Lua plugin (e.g. `mini.base16`); palette = a file in the repo by default (base16 One Dark, close to today's look), **supplied by Stylix on Nix** (owner: "use stylix instead of weird lua themes") | one plugin instead of two theme plugins; same mechanism Stylix uses, so Nix theming needs no Lua changes; `theme.lua` transparency stays |
| Git | fugitive + rhubarb + gitsigns | fugitive + gitsigns; drop rhubarb unless owner uses `:GBrowse` | lean |
| Keep (lazy-loaded) | harpoon, undotree, which-key, gitsigns, lazydev, mason, fidget, treesitter-context, vim-sleuth, lualine, devicons | keep; audit checks cost and lazy-load trigger | owner uses them / small |

## Wider audience (owner, 2026-11-14) — shapes 2a choices, built in stage 3

The owner will later provide Nix configs for WSL as the default dev environment for
other developers. Those developers either keep their own Neovim config/plugins or use
this one; either way theming must be consistent. Consequences for 2a:

- The theme palette is **plain data supplied by the environment** (Stylix), readable by
  any Neovim config — this config is just one consumer. No theme logic that only works
  inside this config.
- Nothing in the core may assume it runs on the owner's machine or for the owner
  (already required); personal preferences (key choices, pinned files, etc.) should be
  easy to tell apart from the core so a later "shared core + personal layer" split is
  cheap. No such split is built in 2a.

## Non-goals (2a)

- New features or UI changes (2b), the Problems workflow (2b), update jobs (2c),
  README/learning aids (2d), Nix (3).
- Changing what keys do (beyond plugin swaps that keep the same action on the same key).

## Anti-goals

- A faster editor that the owner finds harder to use.
- Any plugin that compiles or downloads something on install.
- Benchmarks so noisy the guard check fails randomly.
- Removing something the owner uses without them seeing it in the audit first.

## Constraints

- Neovim ≥ 0.12; Linux (WSL now, NixOS later), maybe macOS; never native Windows.
- `$PATH` on this machine has 86 slow Windows-mount entries (~100–175 ms per missing
  lookup): no synchronous `executable()`/`exepath()` checks at startup or on hot paths.
- `tests/check.sh` (56 checks) must stay green throughout; new behaviour gets new checks.
- Commits use identity `Anton Chernous <czernous_a@hotmail.com>` + Claude co-author trailer.

## Process

1. Benchmark script + baseline numbers.
2. Audit report (per plugin: what it does for the owner, startup cost, build/download
   needs, built-in alternative, verdict, risk) — **owner checkpoint**: veto/approve.
3. Plugin-manager spike (lazy.nvim vs `vim.pack`) with a recommendation — part of the
   same checkpoint.
4. Implement approved verdicts one area at a time, checks green after each.
5. Final benchmark vs baseline; owner tests; whole-branch review.

## Calls made after review (Claude's calls — owner can override)

- **Tree-sitter parsers are exempt from "no build step".** They're compiled by the
  external `tree-sitter` CLI + C compiler from `$PATH` (an external program, goal 3), not
  by a plugin's install hook; on Nix they'll come prebuilt from nixpkgs. nvim-treesitter
  stays, auto-install stays; it's audited for cost/lazy-loading like everything else.
  Mason stays as a **user-initiated** fallback (it downloads only on `:MasonInstall`).
- **Nix layout assumed for the spike:** plugins supplied in a `pack/*/opt` directory
  (lazy-loadable via `packadd`; nixpkgs/home-manager support optional plugins). The spike
  builds a mock packpath of that shape here (no Nix on this machine) and passes if the
  *same* Lua config runs from it with zero network access and still lazy-loads. Final Nix
  wiring is stage 3.
- **Missing external tools never break the editor.** If a tool a feature needs (fzf, rg,
  fd, …) isn't on `$PATH`: one clear warning naming the tool, and the feature falls back
  (e.g. picker uses its Lua sorter / built-in search) or is skipped. A tool becoming a
  requirement (e.g. `fzf` for fzf-lua — not on this machine today) is flagged in the
  audit for the owner to accept, like `rg`/`fd` already are.
- **Benchmarks use the owner's real interactive `$PATH`** (the slow Windows-mount entries
  included) — that's what the owner experiences. The ≤ 50 ms target refers to that.
- **Completion latency is judged per language, plugin-attributable part only:** measured
  with fast servers present here (lua_ls, gopls); a regression = median slower than
  baseline by > 20% *and* > 10 ms. Languages whose server is missing are skipped. Slow
  warm-up servers (jdtls, rust-analyzer) are not used for this comparison.
- **The plan stops at the owner checkpoint:** plan 1 = benchmark + audit + plugin-manager
  spike; implementation is planned after the owner approves verdicts (avoids planning
  throwaway branches).

## Left to the builder

- Exact benchmark mechanics (as long as they're median-of-N and reproducible).
- Exact lazy-load trigger per plugin.
- Which pure-Lua/no-build mode each plugin uses.
- Check ceiling for startup (generous enough not to flake).

## Done when

- Audit approved by owner; approved verdicts implemented.
- Startup ≤ 50 ms median on this machine (or the audit shows why not, and the owner
  accepts the number); no measure slower than baseline.
- No plugin with a build/download step; `tests/check.sh` green, including new checks.
- Step 1 leftovers (goal 8) closed; standards (goal 9) enforced by tripwire-proven checks; palette + polarity mechanism (goal 10) in place.
