# Performance baseline

Recorded 2026-11-14 with `./tests/bench.sh --runs 12 --label baseline`, before any stage 2a change.
Raw data: `tests/bench/baseline.json`. Two full passes agreed within 15% on every measure.

**Machine:** Intel(R) Core(TM) Ultra 7 255U, 14 threads, WSL2. Neovim 0.12.4+v0.12.4. `$PATH`: 101 entries, 86 of them Windows mounts (`/mnt/...`).
Benchmarks use the real interactive `$PATH` on purpose.

## Timings (ms)

Fastest run is the repeatable figure on a shared machine (noise only adds time); median and max show the spread.

| Measure | min | median | max |
|---|---|---|---|
| Launch, wall clock (`nvim +qa`) | 89.4 | 102.0 | 143.1 |
| Bare Neovim launch (`-u NONE`) — the floor | 10.7 | 18.0 | 26.0 |
| Startup, Neovim's internal clock | 77.3 | 81.5 | 105.7 |
| Open csharp fixture until highlighted | 249.7 | 255.3 | 266.3 |
| Open go fixture until highlighted | 114.3 | 131.3 | 137.6 |
| Open java fixture until highlighted | 114.5 | 138.5 | 160.2 |
| Open lua fixture until highlighted | 116.7 | 128.0 | 149.3 |
| Open rust fixture until highlighted | 163.9 | 182.7 | 201.8 |
| Open ts fixture until highlighted | 231.6 | 253.9 | 263.3 |
| Last keystroke → completion menu (go) | 75.4 | 79.0 | 112.5 |
| Last keystroke → completion menu (lua) | 76.4 | 124.8 | 154.3 |

**Config overhead at launch:** about 79 ms on top of bare Neovim (min 89.4 vs 10.7). Stage 2a target: ≤ 15 ms total launch on this machine with a non-AppImage Neovim.

## Allocation per event (bytes of Lua memory, GC stopped, 1000 events)

Exact and load-independent — the instrument for hot paths.

| Event | bytes/event |
|---|---|
| CursorMovedI | 14991 |
| BufEnter | 6244 |
| CursorMoved | 1938 |
| WinScrolled | 1067 |
| TextChangedI | 507 |
| statusline | 177 |
| TextChanged | 113 |
| InsertCharPre | 112 |

## Neovim packaging (measured separately, 15 launches each, wall clock)

| | AppImage (`/opt/nvim/nvim`) | same build, unpacked |
|---|---|---|
| Bare Neovim | 84 ms (51–107) | 11 ms (9–15) |
| With this config | 156 ms (139–178) | 80 ms (70–115) |

The AppImage adds ~75 ms to every launch (it mounts a filesystem image). The benchmark children are started from the already-mounted image, so the numbers above exclude that cost.
