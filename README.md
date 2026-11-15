# Neovim config

A lean, fast, calm Neovim setup that behaves like an IDE: code intelligence,
fixes, formatting, debugging, test running, git, search. No AI features, no
icons or special fonts, no file-tree sidebar, no tabs.

- **Fast**: ready in about 9 ms (bare Neovim is about 4.5 ms). Only the plugin
  manager runs before the first screen; every plugin loads on first use.
- **Portable**: plain Lua. No operating-system or machine-specific code, no
  hard-coded versions or paths. Tools (language servers, formatters, debuggers)
  come from `$PATH`: the language toolchain, a devshell, or your packages.
- **Checked**: 130 automated checks, including rules ("no blocking calls",
  "nothing loads at startup") that are themselves proven able to fail.

Needs **Neovim 0.12 or newer**. Linux and macOS (WSL included); not native Windows.

Contents: [Install](#install) · [First five minutes](#first-five-minutes) ·
[Keys](#keys) · [Languages and tools](#languages-and-tools) ·
[Colours](#colours) · [Debugging](#debugging) · [Running tests](#running-tests) ·
[Nix](#nix) · [Changing things](#changing-things) · [Checks and benchmarks](#checks-and-benchmarks) ·
[Layout](#layout) · [Troubleshooting](#troubleshooting)

## Install

Without Nix:

```sh
git clone https://github.com/czernous/nvim-cfg ~/.config/nvim
nvim            # first start installs the plugins (needs git and a network)
```

Then run `:checkhealth czernous`. It lists every program the config looks for,
whether it was found, and what stops working without it. Nothing is installed
behind your back; a missing tool produces one clear message when you need it.

The basics it expects on `$PATH`:

| Program | Used for |
|---|---|
| `git` | installing plugins, git markers, `:Git` |
| `rg` (ripgrep) | searching inside files |
| `fd` | finding files (falls back to a slower search without it) |
| a C compiler + the `tree-sitter` CLI | building syntax-highlighting parsers (once per language) |
| a clipboard tool (`wl-clipboard`, `xclip`, `win32yank.exe` on WSL; built in on macOS) | `<leader>y` to the system clipboard |

With Nix: see [Nix](#nix). The package brings all of the above.

## First five minutes

The leader key is **Space**.

- `nvim .` in a project opens the start screen with the keys worth knowing.
- Press **Space and wait**: a popup shows what each next key does.
- **`Space p k`**: the cheat sheet. Every key of this config and the built-in
  ones worth knowing, searchable by what they do. Enter presses the key.
- `Space p f` finds files, `Space p g` searches text, `Space p v` opens the folder.
- `:help` opens in the whole window; `q` goes back to your file.

## Keys

`Space p k` is always complete and current (it is generated from
`lua/czernous/keymaps.lua`, the one place keys are defined). The groups:

| Prefix | Group | Examples |
|---|---|---|
| `Space p` | Find | `pf` files, `pg` grep, `pw` word under cursor, `pb` buffers, `pr` reopen last search, `ph` help, `pk` keys, `pv` folder view |
| `Space e` | Problems | `ee` this file, `ea` all files, `en`/`ep` next/previous, `ed` describe, `ef` fixes with preview, `eq` to quickfix |
| `Space b` | Debug | `bb` breakpoint, `bc` start/continue, `bn` `bi` `bo` step, `bv` variables, `bs` stack, `be` value, `br` console, `bq` stop |
| `Space r` | Run tests | `rt` test under cursor, `rf` this file, `ra` all, `rl` last again (`rn` renames) |
| `Space h` | Git change | `hs` stage, `hr` undo, `hp` preview, `hb` who changed this line, `hd` diff |
| `Space g` | Git | `gs` git status window (`s` stage, `u` unstage, `=` diff, `cc` commit, `g?` help) |
| `Space t` | Toggles | `tT` transparency, `tp`/`tP` next/previous palette, `ts` softer/stronger colours, `tg` git letters in the folder view, `tb` line blame |
| `Space 1`–`4`, `Space a`, `Ctrl-e` | Harpoon | pin files and jump to them |
| `g…` | Code | `gd` definition, `grr` references, `grn` rename, `gra` fixes, `gO` outline, `K` documentation |
| | Editing | `Space f` format, `Space s` replace word everywhere, `Space y` copy to system clipboard, `gcc` comment, `Ctrl-Space` select / grow selection |
| | Text objects | `af`/`if` function, `ac`/`ic` class, `aa`/`ia` argument, `ih` git change (e.g. `daf` deletes a function) |

In the folder view (`Space p v`): Enter opens, `-` goes up, edit a name and `:w`
to rename, `dd` + `:w` to delete, `o` + name + `:w` for a new file, **`gm` to move
by typing the destination** (like `mv`; folders are created), `g?` for all keys.
Letters after a name are its git status (`M` modified, `A` added, `?` new, `!` ignored).

Keys that changed from older versions of this config: `docs/perf/changed-keys.md`.

## Languages and tools

A language works when its tools are on `$PATH`. Nothing else to configure.

| Language | Language server | Formatter (`Space f`) | Linting | Debugger | Tests |
|---|---|---|---|---|---|
| Go | `gopls` | gopls | staticcheck (in gopls) | `dlv` | `go test` |
| Rust | `rust-analyzer` | rustfmt (via server) | clippy, when installed | `lldb-dap` or `codelldb` | `cargo test` |
| Java | `jdtls` | jdtls with the project's Eclipse profile; `Space F` runs Spotless | – | not yet (planned with Nix) | `./gradlew test` or `mvn test` |
| Kotlin | `kotlin-language-server` | server | – | not yet | `./gradlew test` |
| C# | `csharp-ls` | server | – | `netcoredbg` | `dotnet test` |
| TypeScript / JavaScript | `vtsls` | `biome` or `oxfmt` (project's own copy first) | `biome` | – | `bun test`, or the project's vitest / jest |
| Lua | `lua-language-server` | `stylua` | – | – | – |
| Python | – | `ruff` | `ruff` | – | – |

- **Problems are reported, never auto-fixed.** No format-on-save, no inline
  error text. Counts are in the status line (`E2 W1`); `Space e e` lists them;
  `fix` appears in the status line when the line under the cursor has a fix
  (`Space e f` lists the fixes, each with a preview).
- A missing server means no completion or documentation for that language, and
  one message saying which program to install. `:MasonInstall <server>` exists as
  a manual fallback for machines without the toolchain.
- Completion appears as you type (Enter accepts, Tab / Shift-Tab move).
  Nothing closes brackets for you.

## Colours

Every colour comes from a **16-colour base16 palette**: a small JSON file. One
renderer turns it into the colour scheme, and a set of rules keeps the result
calm and consistent whatever the palette.

Where the palette comes from, first match wins:

1. `$NVIM_BASE16_PALETTE=/path/to/palette.json` (the word `builtin` instead of a
   path means "ignore Stylix");
2. **Stylix**, when the machine is themed by it: `~/.config/stylix/palette.json`
   or `/etc/stylix/palette.json` is found by itself. Nothing to configure;
   change the system theme and Neovim follows on its next start;
3. the built-in palettes in `palettes/`: Catppuccin Mocha on a dark terminal,
   Catppuccin Latte on a light one.

Adjusting:

| Key | Does |
|---|---|
| `Space t p` / `Space t P` | next / previous built-in palette (remembered; a palette with a light or dark counterpart selects that too) |
| `Space t s` | softer / stronger: fades all text colours towards the background by 0, 10, 20 or 30 % (remembered; default 20 %; never below a readable 6:1) |
| `Space t T` | transparent background on / off |

Built-in palettes (all official base16 schemes, unchanged):

| Dark | Its light counterpart |
|---|---|
| Catppuccin Mocha (default), Macchiato, Frappé | Catppuccin Latte |
| Rosé Pine, Rosé Pine Moon | Rosé Pine Dawn |
| One Dark | One Light |
| Ayu Mirage | Ayu Light |
| Tokyo Night Moon, Tokyo Night Storm | Tokyo Night Light |
| Tokyo City Dark | Tokyo City Light |
| Tomorrow Night | Tomorrow |
| Nightfox | Dayfox |
| 0x96f, Apprentice, Ashes, Blueish, Jabuti, Mission Brogue, Material, Material Palenight, OceanicNext | none published |

On a light terminal only light palettes are used, on a dark one only dark ones. Picking
a palette on the left also selects its counterpart for the other kind of terminal, so
the same theme follows the terminal. A palette without a counterpart leaves the other
choice as it was.

**Your own theme**: put a JSON file in `palettes/` (copy any of them: a `name`,
`"variant": "dark"` or `"light"`, optionally `"pair"` naming its counterpart, and `base00` … `base0F`) and it appears under
`Space t p`; or point `$NVIM_BASE16_PALETTE` at a file anywhere. Thousands of
ready-made schemes: <https://github.com/tinted-theming/schemes> (the `base16`
folder). To change the default palette or softness for everyone, edit `M.themes`
and `M.opts` at the top of `lua/czernous/theme.lua`.

The rules (documented at the top of `theme.lua`, each with a check):

1. dark or light follows the terminal;
2. backgrounds are all-or-nothing: transparent everywhere, or one background
   everywhere; popups are told apart by their border;
3. "the selected item" looks the same in every list;
4. the result is cached, so a normal start replays it in under a millisecond;
5. calm code: names are plain text, punctuation is muted, all keywords share one
   colour, comments are muted but readable, the matching bracket stands out;
6. every border is the same quiet colour and every popup title looks the same,
   whichever plugin draws it.

Plugin colours need no upkeep: the renderer is told which plugins are installed
from the plugin list itself.

## Debugging

`Space b b` sets a breakpoint (a `B` in the margin), `Space b c` starts. While
paused the line is marked `>` and the status line says `debug:stopped`.
`Space b v` shows variables, `Space b e` the value under the cursor, `Space b r`
a console for expressions; `n`/`i`/`o` after `Space b` step.

The debugger program for the language must be on `$PATH` (table above). A
project's `.vscode/launch.json` is offered when present. Rust, C and .NET ask
for the built program to run.

## Running tests

`Space r t` runs the test the cursor is in, `Space r f` the file, `Space r a`
the project, `Space r l` the last run again. The project's own command runs in a
floating terminal, so you see exactly what the tool prints. `q` closes it;
Enter on a `file:line` jumps there. The file is saved first.

## Nix

The flake provides a self-contained package (Neovim, this config, the plugins at
the `lazy-lock.json` commits, basic tools), devshells per language, and an
optional home-manager module. home-manager is not required.

```sh
nix run github:czernous/nvim-cfg                # try it
nix profile install github:czernous/nvim-cfg    # install
nix develop github:czernous/nvim-cfg#go         # Go toolchain + server + debugger (also rust, java, dotnet, web, lua, python)
nix run .#update-plugins                        # in a clone: update the plugins (like :Lazy update)
```

Details, the NixOS and home-manager snippets, and what is and is not yet
verified: **`docs/nix.md`**.

## Automatic updates

Two jobs on GitHub keep the config on the newest versions without breaking it.

| Job | When | What it does |
|---|---|---|
| `checks` | every push, or by hand | On a clean Ubuntu machine: newest stable Neovim, plugins at the `lazy-lock.json` commits, then all checks and tripwires. Separately: evaluates the flake, builds the Nix package and starts it. |
| `update` | Mondays 05:17 UTC, or by hand | Moves every plugin to its newest commit and nixpkgs to its newest revision, puts that on the branch `updates/auto`, and runs `checks` on it. |

What `update` does with the result:

- **everything passes**: it opens a pull request (or refreshes the open one) listing
  what moved, with a link per plugin to the changes. Merging it is the only manual step.
- **something fails**: it opens an issue (or adds to the open one) with what moved and
  which checks failed. Nothing is offered for merging; the next run tries again.
- **nothing moved**: the checks still run on the main branch, so a new Neovim release
  is tested against the config as it is; a failure becomes an issue.

Nothing reaches the main branch by itself. Scheduled runs only start once
`.github/workflows/` is on the default branch.

One-time setting for the pull request: repository *Settings > Actions > General >
Allow GitHub Actions to create and approve pull requests*. Without it the job opens an
issue containing the link to create the pull request.

To run either by hand: *Actions* tab, pick the job, *Run workflow*. The reasons for
this shape are in `docs/adr/0002-update-jobs.md`.

## Changing things

| To | Do |
|---|---|
| add or change a key | edit `lua/czernous/keymaps.lua` (the only place keys are set; the cheat sheet, the popup and the start screen follow) |
| add a language server | add `name = 'program'` to `M.servers` in `lua/czernous/lsp.lua`; put special settings in `after/lsp/<name>.lua` |
| add a formatter | `M.formatters` in `lua/czernous/format.lua` |
| add a debugger | `M.debuggers` in `lua/czernous/debugging.lua` |
| add a test command | a builder in `lua/czernous/test.lua` |
| add a plugin | a spec in `lua/czernous/plugins/`, saying what loads it (a key, a command, an event); then run the checks |
| update plugins | merge the weekly update pull request (see Automatic updates); or by hand: `:Lazy update` (or `nix run .#update-plugins`), run the checks, commit `lazy-lock.json` |
| change an option | `lua/czernous/options.lua` |

Every file starts with a comment saying what it is for and why it is the way it is.

## Checks and benchmarks

```sh
./tests/check.sh                 # everything (about 4 minutes); exit code = failures
./tests/check.sh --tripwires     # proves the rule checks can fail: plants a violation of each
CHECK_ONLY='^theme|^stylix' ./tests/check.sh    # only matching checks
./tests/bench.sh                 # startup, file open, completion, allocations
```

A check that needs a tool this machine lacks is reported as `SKIP` with the
reason. Measurements and how they were taken: `docs/perf/`. Decisions and their
reasons: `docs/adr/`, `docs/superpowers/specs/`.

## Layout

```
init.lua                 loads lua/czernous
lua/czernous/
  init.lua               start-up order; what waits until after the first screen
  options.lua            editor options
  keymaps.lua            every key, in groups (single source)
  lazy.lua               plugin manager setup; $NVIM_PLUGIN_ROOT, $NVIM_CONFIG_ROOT
  plugins/*.lua          plugin specs: what each is for and what loads it
  theme.lua              palettes, the colour rules, cache
  statusline.lua         the status line (built in, text only)
  start.lua              the start screen
  lsp.lua                language servers: which, found how, diagnostics display
  format.lua             Space f: project formatter, else the language server
  fixes.lua              the `fix` hint and the fix list
  debugging.lua          debuggers and the Space b keys
  test.lua               test commands and the floating terminal
  explorer.lua           folder view extras: move by typing, git letters
  help.lua               cheat sheet, full-window help
  treesitter.lua         syntax parsers and highlighting
  project.lua            "which project is this file in?"
  tools.lua              finding programs on $PATH without waiting
  health.lua             :checkhealth czernous
after/lsp/*.lua          per-server settings
palettes/*.json          built-in colour palettes
nix/, flake.nix          Nix package, devshells, module, plugin updater
.github/                 the checks and the weekly update, run by GitHub
tests/                   checks, tripwires, benchmarks, fixtures
docs/                    measurements, decisions, Nix notes
```

Environment variables the config reads:

| Variable | Meaning |
|---|---|
| `NVIM_BASE16_PALETTE` | path to a palette file, or `builtin` |
| `NVIM_PLUGIN_ROOT` | folder holding the plugins; then nothing is installed or updated (Nix sets it) |
| `NVIM_CONFIG_ROOT` | folder holding this config when it is not `~/.config/nvim` (Nix sets it) |

## Troubleshooting

| Symptom | Look at |
|---|---|
| no completion / documentation in a language | `:checkhealth czernous`: is its server found? `:checkhealth vim.lsp` for the running ones |
| `Space f` does nothing useful | `:ConformInfo` shows which formatter would run and why not |
| no highlighting for a language | the `tree-sitter` CLI and a C compiler must be on `$PATH` the first time |
| colours look wrong after changing palettes or plugins | restart Neovim (the cache rebuilds itself); `:checkhealth czernous` says which palette is in use |
| a system theme change (Stylix) is not picked up | it applies on the next start of Neovim |
| slow start | `nvim --startuptime /tmp/start.log .` and read the largest steps; `./tests/bench.sh` for numbers |
| `Space y` does not reach the system clipboard | install a clipboard tool (see Install) |
