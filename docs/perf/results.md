# Stage 2a results

2026-11-14 · Neovim 0.12.4 (unpacked build) · `./tests/bench.sh --runs 12`, two passes each ·
raw data: `docs/perf/data/baseline-unpacked.json` (before) and `docs/perf/data/part2-final.json` (after).

Timings are **fastest / median** in ms. A figure marked ⚠ did not agree between the two passes
(more than 15% apart on the fastest run) on this busy, shared machine: treat it as a range, not a result.

## Launch

| | Before | After |
|---|---|---|
| **Ready** (start of process → usable, shutdown excluded) | not measured that way; start+quit below | 11.6–13.8 fastest ⚠, median 15.3 |
| Bare Neovim ready (the floor) | — | 5.7 / 5.9 |
| Start + quit (`nvim +qa`) | 76.1 / 95.7 | 19.1 / 20.9 |
| Neovim's internal startup clock | 115.6 / 139.7 ⚠ | 9.5 / 10.0 |

Target was ≤ 15 ms ready: the fastest runs are 11.6–13.8 ms (two passes), median 15.3 ms. The config adds about 8 ms to bare Neovim; this morning `nvim +qa` took 76 ms and now takes 19 ms.

## Opening a file until it is highlighted (fastest / median, ms)

| Language | Before | After |
|---|---|---|
| csharp | 232.0 / 246.4 | 173.1 / 198.4 |
| go | 91.9 / 117.8 ⚠ | 41.2 / 49.0 |
| java | 127.4 / 148.4 ⚠ | 53.9 / 65.3 |
| lua | 100.4 / 118.0 ⚠ | 40.3 / 48.3 |
| rust | 185.6 / 227.1 | 101.5 / 112.3 |
| ts | 216.9 / 232.9 | 165.6 / 195.5 |

## Completion: last keystroke → menu with the language server's suggestions (fastest / median, ms)

| Language | Before (nvim-cmp) | After (blink.cmp) |
|---|---|---|
| go | 78.1 / 79.1 | 3.7 / 5.4 |
| lua | 73.5 / 126.7 | 1.6 / 3.8 |

Most of nvim-cmp's delay was its default 60 ms wait before showing the menu (a setting), not slowness as such. The "before" column counted the menu being visible at all; the "after" column waits for language-server items.

## Memory allocated per event (bytes; exact, repeatable)

| Event | Before | After | |
|---|---|---|---|
| CursorMovedI | 14,963 | 8,334 | still mostly the completion engine (blink.cmp); less than nvim-cmp but more than the ~2.4 KB estimated in the audit |
| TextChangedI | 508 | 1,751 | **higher**: blink.cmp does its matching here |
| InsertCharPre | 112 | 624 | **higher**: blink.cmp |
| CursorMoved | 1,939 | 1,194 | lualine gone (our statusline: 0); what is left is treesitter-context (~510) and built-in matchparen (~160) |
| WinScrolled | 1,067 | 1,553 | **higher**: language-server semantic tokens (~790) now counted with a server attached, treesitter-context (~510) |
| BufEnter | 6,272 | 2,509 | lualine gone; which-key 1,700, treesitter-context 500, gitsigns 420, our statusline 416 |
| TextChanged | 114 | 113 | unchanged |
| statusline | 177 | 177 | the cost of asking Neovim to render the line; our statusline runs no Lua on redraw |

Per-plugin split: `docs/perf/data/allocation-by-autocmd-group-final.txt` (only handlers registered in a named group can be attributed; blink.cmp's are not, so its share is the remainder).

## Plugins

30 → 21. Loaded before the first screen: none on a normal start (the theme is replayed from a cache; the plugin manager itself is the only third-party code that runs).

## Checks

`./tests/check.sh`: 95 pass, 0 fail, 2 skipped (C# and TypeScript servers are not on this machine's `$PATH`). `./tests/check.sh --tripwires`: 12 deliberate violations, each makes its check fail.

## Not done / open

- Opening a file: both runs had unstable figures for some languages; the direction (roughly half) is consistent but no single number is quotable for those marked ⚠.
- Three per-keystroke allocation figures went up (blink.cmp in insert mode, semantic tokens on scroll).
- The default theme is a stand-in (Catppuccin, to match the owner's terminal); a calmer default and the Stylix hookup are later work.
- JS/TS and C# could not be exercised end to end on this machine (no Node/Bun; csharp-ls not on `$PATH`).

## Addendum: startup in the owner's real terminal (2026-11-14, later)

`tests/bench.sh` runs Neovim without a screen, which hides costs that only exist with a
terminal UI attached. The owner's own `--startuptime` log (`nvim .` in their terminal)
showed 20.8 ms: 5.5 ms Neovim itself, 6.6 ms the plugin manager, ~2.3 ms applying the
cached theme, 2.4 ms reading the history file (ShaDa), the rest keymaps/options/statusline.

Changes made from that log: the history file is read just after the first screen instead
of before it; the theme cache is stored as msgpack instead of JSON; lazy.nvim's package-spec
scan is off; extended `%` matching loads with the first file.

CPU time from process start to UIEnter in a terminal UI (`nvim .`, 25 runs, the figure the
start screen shows; measured through a pseudo-terminal, so absolute values are indicative):

| | Before | After |
|---|---|---|
| fastest | 14.6 ms | 11.0 ms |
| median | 20.1 ms | 17.5 ms |

Headless ready (`nvim .`): 10.9 → 9.3 ms fastest (bare Neovim 4.3 ms).

## Addendum: file explorer

Measured first/later opens of `<leader>pv` on this machine: built-in netrw 693 ms / 7–14 ms
(it looks up remote-file programs on `$PATH` when it loads); oil.nvim 34 ms / 0.2–1 ms.
oil.nvim is used; a check fails if the first open exceeds 200 ms.
