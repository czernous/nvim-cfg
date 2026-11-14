# Step 1 — A working, properly modular Neovim config

Date: 2026-11-14 · Repo: `~/.config/nvim` · Neovim ≥ 0.12 (currently 0.12.4)

## Why

The owner doesn't want to spend hours configuring and re-configuring editors.
The end goal is a reproducible, very fast, ergonomic environment, eventually
driven by Nix/NixOS (with per-language devshells and Stylix theming) — but the
plain Lua config must stay usable on machines without Nix, and it has to be in
good order *first*. This document covers only that first step.

The work is in three stages; this is stage 1:

1. **Make it work and make it modular** (this doc).
2. Restructure/optimise: better plugins, drop unused kickstart leftovers, lazy-loading/startup speed.
3. Reuse/Nix integration (devshells, Stylix, flake).

## Who uses it

- Not an advanced Vim user. Must be able to find out **what any keymap does**
  from inside Neovim, and from the README.
- Config started from kickstart.nvim; contains things the owner doesn't use.
- Machines: Linux (WSL today, NixOS later), possibly macOS later. **Never native Windows.**
- Languages actually used: **Go, Rust (incl. Leptos), C#/.NET, JS/TS (Bun), Java**
  (a Java project exists in this WSL machine), plus **Lua** for the config itself.

## Goals

1. **Every listed language works** when its toolchain/server is on the machine:
   treesitter highlighting, LSP attach, completion, go-to-definition/references,
   diagnostics, and formatting.
2. **Language servers come from `$PATH`** — the language's own toolchain or a
   devshell (e.g. `gopls`, `rust-analyzer` from rustup, `jdtls`/C# server from a
   devshell). The config enables a server **only if its executable is found**;
   missing servers are silently skipped (no error spam).
3. **Mason is a manual fallback only**: no `ensure_installed`, no automatic
   enabling, its bin dir appended to `$PATH` (`PATH = "append"`) so a
   toolchain/devshell binary always wins over Mason's copy. `mason-lspconfig`
   is removed — the PATH check in goal 2 covers Mason-installed servers too.
3a. **Multiple language versions are normal** (e.g. several .NET SDKs, Java
   8/17/21, different Rust toolchains per project). The config **never names or
   pins a version**; the project's environment picks it — a devshell, `global.json`
   (.NET's `dotnet` muxer honours it), `rust-toolchain.toml` (the rustup proxy
   honours it), `JAVA_HOME`. Concretely:
   - servers are resolved from `$PATH` when the server starts, so opening
     Neovim inside a project's devshell gets that project's versions;
   - Java: `jdtls` itself needs a recent JDK to *run*, but the project's target
     JDK must come from the environment (`JAVA_HOME` or jdtls'
     `java.configuration.runtimes` built from env vars) — never a hardcoded path;
   - C#: the server must run via the `dotnet` on `$PATH` so `global.json` applies.
   - Supported workflow: one Neovim per project (launched in that project's
     environment). Switching between projects with different versions inside a
     single Neovim session is **not** a goal in stage 1.
4. **Clear modules, one job per file.** A person should guess the right file
   from its name. Each plugin's spec owns its own setup and keymaps (the
   current split between `plugins/` specs and a separate `cfg/` folder goes away).
5. **Per-language special settings in one file per language**, using Neovim's
   native `after/lsp/<server>.lua` override mechanism (merged on top of
   nvim-lspconfig's defaults). Languages with no special needs get no file.
   Existing Leptos settings (leptosfmt override, ignored `server` proc-macro)
   move to `after/lsp/rust_analyzer.lua`; `lua_ls` settings likewise.
   *(My call)* The leptosfmt `overrideCommand` applies **only when `leptosfmt`
   is executable**; otherwise rust-analyzer uses plain rustfmt. (It's absent on
   this machine; unconditional use would break all Rust formatting.)
6. **Keymaps are discoverable and don't clash:**
   - every mapping has a `desc` (shows in which-key and `:Telescope keymaps`);
   - no mapping is both a complete key *and* the prefix of another mapping
     (that's what makes Neovim pause). Known clashes today:
     `<leader>d` vs `<leader>ds`; `<leader>s` vs `<leader>swn/swp`;
     `<leader>f` vs `<leader>fb/fh`; `tgR` shadows the `t` motion;
     global `<C-k>` (quickfix next) is overridden by LSP signature help in LSP buffers;
   - which-key group labels match the mappings that actually exist
     (e.g. there is no `<leader>s` "Search" group today);
   - README gets a keymap reference table, grouped by purpose.
7. **Treesitter works for any language**: the listed languages' parsers
   (`go`, `gomod`, `rust`, `c_sharp`, `java`, `javascript`, `typescript`, `tsx`,
   `lua`, plus the existing list) are kept installed, and a missing parser for any
   other filetype is installed on first open when the `tree-sitter` CLI is available.
8. **One swappable theme spot.** All colorscheme choice lives in one module so
   Stylix (stage 3) can take over later. Behaviour in stage 1 stays onedark-warm.
8a. **Terminal transparency just works, without breaking themes.** Neovim can't
   detect terminal transparency, so instead it doesn't paint the editor
   background and lets the terminal (transparent or not) show through.
   - One setting in the theme module (`transparent = true` by default) — no
     functions to call manually.
   - Applied by a `ColorScheme` autocmd, so it survives `:colorscheme X`
     for **any** theme, not just onedark (theme-agnostic: clears `bg` on
     editor-area groups like `Normal`, `NormalNC`, `SignColumn`, `EndOfBuffer`,
     `LineNr`, statusline/winbar/tabline where sensible).
   - Floating windows/popups (completion menu, hover docs, Telescope, which-key)
     **keep** a background so they stay readable over transparent terminals.
   - Toggleable at runtime with a described keymap (e.g. `<leader>tt`... builder
     picks a non-clashing key) for quick comparison while the owner tests.
   - Owner will test and steer visual details; exact group list is the builder's call.
9. **All plugins updated**, `lazy-lock.json` committed afterwards.
10. **A repeatable headless check** committed to the repo (e.g. `tests/check.lua`,
    runnable as one command documented in the README) that, for each language:
    opens a small fixture project, asserts a treesitter highlighter is active,
    asserts the LSP attaches **if the server executable exists** (reports
    "skipped: <server> not on PATH" otherwise), and fails on any error message.
    It also fails on keymaps without `desc` and on prefix clashes (goal 6).
    Stages 2 and 3 reuse it as a regression test.

11. **Fixes from the critique of the current setup** (agreed for stage 1):
    - Diagnostics findable **without virtual text** (owner: virtual text hurts
      performance; that's why they reached for Trouble). Keep `virtual_text`
      and signs off; rely on underline, `severity_sort = true`, lualine's
      error/warning counts, `]d`/`[d` with float, and Trouble's diagnostics
      list (now working). Choosing the long-term list UI (Trouble vs improved
      quickfix) is stage 2.
    - Fixed `signcolumn = "yes"` so gitsigns doesn't shift text.
    - `<leader><leader>` (`:so`) only acts in Lua/Vim buffers; elsewhere a short
      warning, not an error.
    - One format key `<leader>f`: LSP formatting when an attached client supports
      it, otherwise Neoformat. (`<leader>nf` may stay as an alias.)
    - No duplicate plugin specs; no keymaps created as side effects of loading
      a plugin spec file.
    - A server executable that exists but fails to start (e.g. a rustup proxy
      without the `rust-analyzer` component, as on this machine) must not spam
      errors.

## Non-goals (stage 1)

- Swapping plugins (Trouble vs improved quickfix, nvim-cmp vs blink.cmp,
  Neoformat vs conform.nvim, Telescope vs alternatives). Stage 2.
  Exception: removing `mason-lspconfig` (goal 3).
- Removing unused kickstart features. Stage 2 — owner approves each removal.
- Startup-time optimisation / lazy-loading work (just don't make it worse).
- Nix, flakes, devshells, Stylix. Stage 3.
- Native Windows support.

## Anti-goals (would make this a failure even if it "works")

- Any machine- or OS-specific code in the config (no WSL/hostname checks).
  Machine differences belong to the machine (e.g. clipboard: install
  `win32yank.exe` on WSL; Neovim auto-detects it).
- Keymaps changing silently. Every changed key is listed for the owner.
- Error popups/notifications when a language's tools aren't installed.
- Hardcoded per-machine paths (Java runtime, Mason paths, home dirs).
- Hardcoded language/SDK versions anywhere in the config.

## Constraints

- Neovim ≥ 0.12 (nvim-treesitter `main` branch requirement; already documented).
- Plugin manager stays lazy.nvim in stage 1.
- Namespace stays `czernous`.
- Machine facts (2026-11-14, this WSL box): on PATH — go, cargo/rustc,
  rust-analyzer (rustup proxy), java, dotnet, tree-sitter, rg, fd, make, gcc.
  Only in Mason — gopls, jdtls, lua-language-server. Absent — bun, node,
  any C# server, stylua, biome, prettier. So JS/TS LSP and formatting cannot be
  verified end-to-end on this machine; the check must report them as skipped,
  not failed.

## Decisions already made

- Servers from `$PATH` first, Mason as manual fallback (owner agreed).
- Config is not WSL-specific (owner's rule).
- Theme must be replaceable by Stylix later (owner plans to use it).

## My calls (owner can override)

- **Proposed module layout** (builder may adjust names, not the principle):
  ```
  init.lua                    -> require('czernous')
  lua/czernous/
    init.lua                  load order only
    options.lua               (was set.lua)
    keymaps.lua               (was remap.lua) — global, plugin-independent keys only
    lazy.lua                  bootstrap + setup, imports czernous.plugins
    theme.lua                 the single theme spot
    lsp.lua                   LspAttach keymaps, capabilities, PATH-based enabling
    plugins/
      ui.lua                  colorschemes, lualine, devicons, which-key
      editor.lua              harpoon, undotree, sleuth, neoformat
      git.lua                 fugitive, rhubarb, gitsigns
      search.lua              telescope (+fzf-native)
      treesitter.lua          treesitter, textobjects, context, incremental selection
      completion.lua          nvim-cmp, luasnip, sources
      lsp.lua                 lspconfig, mason, lazydev, fidget
      diagnostics.lua         trouble
  after/lsp/
    rust_analyzer.lua  lua_ls.lua  (jdtls.lua etc. only if needed)
  tests/
    check.lua
    fixtures/{go,rust,csharp,ts,java,lua}/  minimal projects
  ```
- **Server list:** one explicit table of servers to try, in `lsp.lua`:
  `gopls, rust_analyzer, lua_ls, jdtls, csharp_ls, vtsls` (plus any the owner
  adds — adding a language = one line). Enabled when `cmd[1]` is executable.
- **Java:** start with nvim-lspconfig's `jdtls` config (workspace dir under
  `stdpath('cache')`, no hardcoded paths). Add `nvim-jdtls` only if the owner's
  real project doesn't work with it.
- **C#:** `csharp_ls` (installable with `dotnet tool install -g csharp-ls`) in
  stage 1; evaluating Roslyn is stage 2.
- **JS/TS:** `vtsls`; Biome/Prettier formatting via existing Neoformat when the
  project has the tool installed.
- **Keymap conflict resolution rules:** keep the owner's most-used keys
  (`<leader>pf`, `<leader>pv`, `<leader>s` substitute, harpoon keys, `<leader>y`,
  `<C-d>/<C-u>` etc.) unchanged; move the *less common* member of each clash.
  Prefer Neovim 0.11+ built-in LSP defaults where they already exist
  (`grn` rename, `gra` code action, `grr` references, `gri` implementation,
  `gO` document symbols, `<C-s>` signature help in insert mode) — keep the
  kickstart aliases only if they don't clash. Final list of changed keys goes
  in the README and the hand-over message.

## Left to the builder

- Exact file names within the layout principle; exact fixture contents.
- Exact replacement keys for clashes, following the rules above.
- Which extra treesitter parsers to keep beyond the listed languages.
- How the check script is invoked (as long as it's one documented command).

## Done when

- `tests/check.lua` passes on this machine: Go, Rust, Java, Lua fully green;
  C# green if `csharp-ls` is installed, else reported skipped; JS/TS reported
  skipped (no node/bun here).
- The owner's real Java project opens with LSP working.
- No `cfg/` folder; every file has one job; README has keymap table,
  "adding a language" and "running the check" sections.
- Plugins updated and lockfile committed.
