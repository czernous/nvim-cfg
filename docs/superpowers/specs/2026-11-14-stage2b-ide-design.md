# Stage 2b — errors & fixes, debugging, tests, help

Date: 2026-11-14 · branch `step1-modular` · builds on stage 2a (`docs/perf/results.md`).
Owner said "carry on, get these out of the way, commit, push"; the choices below are
Claude's calls, each reversible. Stage 3 (Nix, Stylix, with/without-Nix performance
comparison) follows.

## Rules carried over (all enforced by existing checks)

Nothing loads before the first screen; no blocking calls; no font-dependent symbols; tools
come from `$PATH` (toolchain/devshell), never auto-installed; missing tool = one clear
message; every key in `keymaps.lua` with a description; every new behaviour has a check
seen failing first. **New for this stage:** a check that none of the new plugins is loaded
until its feature is first used, and that ready time stays within the launch budget.

## 1. Errors and fixes ("Problems", `<leader>e`)

- **"A fix is available" is shown in the statusline** (`fix` after the problem counts) when
  the language server offers a quick fix on the cursor's line. Asked only when the line
  has a problem, only after the cursor rests (`CursorHold`), asynchronously — no work
  while moving.
- **Fixes are previewed before they are applied:** `<leader>ef` (and `gra`, `<leader>ca`)
  list the fixes with a diff of what each would change (actions-preview.nvim, Telescope
  backend, loaded on first use).
- **Formatting and lint violations are reported, not auto-fixed** (owner): where a
  project's tool speaks the language-server protocol it is added as a server found on
  `$PATH` — Biome (JS/TS/JSON/CSS: lint + formatting diagnostics), Ruff (Python); Rust
  runs clippy through rust-analyzer when `cargo clippy` exists; Go gets gopls' staticcheck
  analyses. Java: no such channel exists outside the build; Spotless stays on `<leader>F`.
- Not done: inline virtual text (owner: performance), auto-fix on save, format on save.

## 2. Debugging (`<leader>b`)

- nvim-dap only (pure Lua), loaded on the first debug key. No separate UI plugin: its
  built-in floating widgets show variables and evaluate expressions; the REPL is a normal
  buffer. Breakpoint and "stopped here" markers are plain letters (`B`, `>`).
- Adapters from `$PATH`, configured only when found (background lookup, like servers):
  Go `dlv`; Rust/C/C++ `lldb-dap` (or `codelldb`); .NET `netcoredbg`. Projects'
  `.vscode/launch.json` files are honoured. Java debugging needs the java-debug bundle
  inside jdtls and is deferred to the Nix stage, where the devshell can supply it.
- Starting a session with no adapter for the filetype says which program is missing.
- `:checkhealth czernous` lists the adapters.

## 3. Running tests (`<leader>r`)

- No plugin. `test.lua` builds the project's own test command for the file's language
  (Go `go test`, Rust `cargo test`, Java `./gradlew test --tests`, .NET `dotnet test
  --filter`, JS/TS `bun test`), for the test under the cursor (found with treesitter),
  the file, or the whole project, and runs it in a floating terminal: real output,
  colours, `q` closes, `gF` on a `file:line` jumps there. `<leader>rl` repeats the last run. (`<leader>t` stays for toggles; `<leader>rn` rename is unaffected.)

## 4. Help

- `<leader>pk`: a clean cheat sheet — only this config's keys and the built-ins worth
  knowing, as key / what it does / group (replaces Telescope's raw mapping dump).
- `:help` opens in the whole window; `q` returns to where you were.

## 5. Theme

A calmer default and the Stylix hookup move to stage 3, where Stylix supplies the palette
system-wide; the mechanism (`$NVIM_BASE16_PALETTE`, polarity, transparency rules) is in place.

## Done when

All checks green (including the new "nothing new loads until used" check), launch budget
held, changed keys documented, branch pushed.
