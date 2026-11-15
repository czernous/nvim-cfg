# ADR 0002 — Updates: proposed by a weekly job, adopted by merging

Status: **proposed** (2026-11-15; the jobs have not completed a run yet)

## Context

The config should stay on the newest stable Neovim, plugins and nixpkgs with as little
manual work as possible, and must never be broken by an update. `lazy-lock.json` pins
the plugins and `flake.lock` pins nixpkgs; Neovim itself is whatever the machine has.

## Decision

Two GitHub Actions workflows.

- `checks.yml` runs on every push and can be called by another workflow. Job `linux`:
  clean Ubuntu runner, newest stable Neovim, plugins installed by lazy.nvim at the
  locked commits, `./tests/check.sh` and `--tripwires`. Job `nix`: `nix flake check`,
  `nix build .#neovim`, and a start of the built editor that must see every locked plugin.
- `update.yml` runs weekly. It moves both lock files to the newest versions, pushes
  that to the branch `updates/auto`, calls `checks.yml` on it, then opens a pull
  request when everything passes or an issue saying what moved and what failed.

No versions are named in either: each run downloads the newest stable Neovim, so a
Neovim release is tested by the next run even when no plugin moved.

## Options considered

| | Chosen: pull request when green | Commit straight to the main branch when green | Only report, update by hand |
|---|---|---|---|
| Manual work per update | one merge | none | run the updater, the checks, commit |
| Can something untested reach the main branch | no | no, but a check that is missing lets a breakage through unseen | no |
| Owner sees what changed before using it | yes (list and links in the pull request) | only afterwards | yes |

A single plugin updater is used for both worlds (`nix/update-plugins.lua`): it writes
the same file `:Lazy update` writes, so plain machines and Nix builds get the same commits.

## Consequences

- Updates arrive at most a week late, and only after a merge.
- All plugins move together. When the checks fail, the issue lists what moved with a
  link per plugin, but finding the one responsible is manual (put one plugin's old
  commit back, `:Lazy restore`, run the checks). Updating plugin by plugin was not
  built: it multiplies the run time by the number of plugins that moved.
- The `linux` job has no language servers except Lua's, so checks that need gopls,
  jdtls, rust-analyzer and others are skipped there, as they are on any machine
  without them.
- The `nix` job runs Nix on an Ubuntu runner, not NixOS, and does not run
  `./tests/check.sh` against the built package yet.
- Pull requests opened by the job do not start `checks.yml` again (GitHub does not let
  a workflow's own token trigger workflows); the same commit was checked inside the
  update run, and the pull request shows that result.
