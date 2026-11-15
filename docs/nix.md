# Nix

Status: **the flake has not been evaluated yet** — it was written on a machine
without Nix. What *is* checked (by `./tests/check.sh`, no Nix needed) is the
contract the flake relies on:

| Check | What it proves |
|---|---|
| `runs_from_supplied_plugin_folder` | the config starts and highlights a file with plugins handed over in a read-only folder shaped like the Nix store one (`$NVIM_PLUGIN_ROOT`), installing and writing nothing |
| `nix_plugin_sources_match_specs` | `nix/plugin-sources.json` names every plugin in `lazy-lock.json`, with the address the plugin specs use |
| `runs_from_another_config_folder` | the config runs from a folder that is not `~/.config/nvim` (`$NVIM_CONFIG_ROOT`), started the way the Nix wrapper starts it: modules, language-server settings and palettes are all found |
| `stylix_palette_picked_up` | Stylix's palette file is followed without any setting |

## Using it

The package is self-contained: Neovim, this config, the plugins and the basic
tools. No home-manager and no clone in `~/.config` are needed.

```sh
nix run github:czernous/nvim-cfg                 # try it
nix profile install github:czernous/nvim-cfg     # install for your user
```

NixOS, without home-manager (with the flake as input `nvim-cfg`):

```nix
environment.systemPackages = [ inputs.nvim-cfg.packages.${pkgs.system}.default ];
```

With home-manager: `imports = [ inputs.nvim-cfg.homeManagerModules.default ];`
and `programs.czernous-nvim.enable = true;` (it installs the same package and
sets `EDITOR`).

The self-contained package keeps its data (history, compiled parsers, the
palette you picked) under the name `czernous-nvim` (`~/.local/share/czernous-nvim`
...), apart from a plain `~/.config/nvim` setup on the same machine.

## First run on a Nix machine

The `nix` job in `.github/workflows/checks.yml` does this on every push (evaluate,
build, start), and the weekly `update` job creates and moves `flake.lock`; see
"Automatic updates" in the README.

```sh
nix flake check                 # evaluates everything
nix build .#neovim              # the self-contained package
nix develop .#go                # a devshell; also rust, cpp, java, dotnet, web, lua, python
nix run .#update-plugins        # in a clone: move lazy-lock.json to the newest commits
```

Things most likely to need a fix on first evaluation:

- `nix/plugins.nix` fetches each plugin with `builtins.fetchGit` by commit. If a
  fetch fails the error names the plugin.
- package names in `nix/devshells.nix` are nixpkgs' current ones as far as known
  (`delve`, `lldb`, `jdt-language-server`, `csharp-ls`, `netcoredbg`, `vtsls`...).
- `nix/package.nix` passes `--cmd 'set rtp^=<config>' -u <config>/init.lua` to
  Neovim through the wrapper; the same command line is what the check
  `runs_from_another_config_folder` runs here.

## A faster linker (mold)

The `rust` and `cpp` devshells carry [mold](https://github.com/rui314/mold), a much
faster drop-in for the default linker (`ld.bfd`). Having it on `$PATH` changes
nothing by itself; a project opts in:

- Rust, in the project's `.cargo/config.toml`:
  `[target.x86_64-unknown-linux-gnu]` / `rustflags = ["-C", "link-arg=-fuse-ld=mold"]`
  (or run a single command as `mold -run cargo build`);
- C / C++ with CMake 3.29 or newer: `-DCMAKE_LINKER_TYPE=MOLD` (in a preset:
  `"CMAKE_LINKER_TYPE": "MOLD"` under `cacheVariables`); older CMake:
  `-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=mold`.

Linux only. Not measured here.

## Who manages the plugins

| | default (self-contained) | `neovim-lazy` / `selfContained = false` |
|---|---|---|
| Neovim, language servers, formatters, debuggers | prebuilt by Nix | prebuilt by Nix |
| Config | from the Nix store | your clone at `~/.config/nvim` |
| Plugins | Nix: the store, at the `lazy-lock.json` commits; no network at run time | lazy.nvim installs and updates them |
| Updating plugins | `nix run .#update-plugins`, then rebuild | `:Lazy update` |
| lazy.nvim's job | loading each plugin on first use, nothing else | managing and loading |

`update-plugins` is `:Lazy update` for the Nix-managed mode: it asks each
plugin's repository for its newest commit (or newest release, for the plugins
that follow releases), rewrites `lazy-lock.json` in the layout lazy.nvim itself
writes, and prints what moved (`^ which-key.nvim 0000000 -> 3aab214 (main)`).
`--check` only shows. It also runs without Nix: `nvim -l nix/update-plugins.lua`.
Tested on this machine against the real repositories (a branch plugin and a
release plugin); the rewritten file was byte-identical to lazy.nvim's.

Every plugin the config uses is fetched this way, so none is left for lazy.nvim
to install. No plugin here has a compiled part (completion uses its Lua matcher
by choice); syntax parsers are compiled on first use by the `gcc` and
`tree-sitter` the package puts on `$PATH`. Prebuilt parsers from nixpkgs are a
possible later step.

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
`docs/perf/results.md`): `nix build .#neovim` and `.#neovim-lazy` against a
plain install of the same Neovim version.
