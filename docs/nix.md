# Nix

Status: **the flake has not been evaluated yet** — it was written on a machine
without Nix. What *is* checked (by `./tests/check.sh`, no Nix needed) is the
contract the flake relies on:

| Check | What it proves |
|---|---|
| `runs_from_supplied_plugin_folder` | the config starts and highlights a file with plugins handed over in a read-only folder shaped like the Nix store one (`$NVIM_PLUGIN_ROOT`), installing and writing nothing |
| `nix_plugin_sources_match_specs` | `nix/plugin-sources.json` names every plugin in `lazy-lock.json`, with the address the plugin specs use |
| `stylix_palette_picked_up` | Stylix's palette file is followed without any setting |

## First run on a Nix machine

```sh
nix flake check                 # evaluates everything
nix build .#neovim              # Neovim + basic tools; plugins by lazy.nvim
nix build .#neovim-pinned       # plugins from the store (lazy-lock.json commits)
nix develop .#go                # a devshell; also rust, java, dotnet, web, lua, python
```

Things most likely to need a fix on first evaluation:

- `nix/plugins.nix` fetches with `builtins.fetchGit` by commit and branch. A
  lockfile commit that is a release tag not on the branch tip history would fail
  to fetch; the error names the plugin.
- package names in `nix/devshells.nix` are nixpkgs' current ones as far as known
  (`delve`, `lldb`, `jdt-language-server`, `csharp-ls`, `netcoredbg`, `vtsls`...).

## Two ways to run

| | default | pinned |
|---|---|---|
| Neovim, language servers, formatters, debuggers | prebuilt by Nix | prebuilt by Nix |
| Plugins | lazy.nvim installs them; `:Lazy update` updates and rewrites `lazy-lock.json` | Nix store, the `lazy-lock.json` commits; no network at run time |
| Config | your clone at `~/.config/nvim` | your clone, or `linkConfig = true` (read-only link to the flake) |
| Updating plugins | `:Lazy update`, commit `lazy-lock.json` | update on a default machine, commit, rebuild |

lazy.nvim stays in both: on a pinned machine it installs nothing and only loads
each plugin on first use, which is what keeps the start fast.

## Colours (Stylix)

All colours come from a 16-colour base16 palette file. With Stylix enabled the
config reads the file Stylix writes (`~/.config/stylix/palette.json`, or
`/etc/stylix/palette.json` on NixOS); without it, the built-in palette for the
terminal's polarity (`palettes/`). `$NVIM_BASE16_PALETTE` names any other file;
the word `builtin` there ignores Stylix. `:checkhealth czernous` says which is
in use.

To see the Stylix path on a machine without Nix, put a palette in Stylix's
format at `~/.config/stylix/palette.json` (16 keys `base00`…`base0F`, colours
without `#`); delete the file to go back to the built-in palette.

## Performance with and without Nix

Measured so far, on a machine without Nix (`./tests/bench.sh`, headless, 3
alternating rounds of 10 starts, best start of each round): plugins from lazy's
own folder -- ready 10.0, 9.3, 9.7 ms; plugins from a supplied read-only folder
shaped like the Nix one -- 10.0, 9.9, 12.3 ms (the last round ran while other
measurements were using the machine). No difference beyond run-to-run noise in
the two clean rounds.

Still to measure on a Nix machine (same command, same table in
`docs/perf/results.md`): `nix build .#neovim` and `.#neovim-pinned` against a
plain install of the same Neovim version.
