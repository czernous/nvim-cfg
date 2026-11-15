# ADR 0001 — Plugin manager: keep lazy.nvim

Status: **accepted** (owner, 2026-11-14)

## Context

Neovim 0.12 ships a built-in plugin manager, `vim.pack`. "Built-in first" is a rule of
this config, so the default expectation would be to switch. Requirements: load plugins
on first use (launch ≤ 15 ms), install from a lockfile on plain machines, and run
unchanged with plugins supplied by Nix (read-only folder, no network).

## Options measured (sandbox copies of the lean prototype, same plugins and triggers)

| | lazy.nvim | `vim.pack` + our load-on-demand helper |
|---|---|---|
| Launch, fastest of 10 | 13.9 ms | 14.1 ms |
| Lazy-loading | built in (events, commands, keys, `require`) | not provided; ~80 lines of our own code |
| Runs offline from an external plugin folder | yes, with one hook (`NVIM_PLUGIN_ROOT` → lazy's `root`, installs off) — tested read-only | yes, no hook (plugins already on `packpath` are used as-is) — tested |
| Lockfile | `lazy-lock.json` | `nvim-pack-lock.json` |
| Maturity | years of use, profiler, UI | new in 0.12, API still settling |
| Problems seen in the spike | none | our helper replayed `InsertEnter` wrongly: completion never triggered |

## Decision

Keep lazy.nvim. The built-in manager is not faster, and choosing it means owning the
lazy-loading code ourselves — the spike's bug is exactly the kind of thing that code
would keep producing. lazy.nvim satisfies the Nix requirement with a single,
OS-independent hook.

## Consequences

- One third-party dependency remains at the core of the config (3 ms of the launch budget).
- Stage 3 (Nix) sets `NVIM_PLUGIN_ROOT`; the Lua config is otherwise identical on and off Nix.
- Revisit when `vim.pack` gains lazy-loading upstream: the swap is then a small change
  because plugin specs are already declarative.
