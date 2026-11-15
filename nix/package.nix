# Neovim, wrapped so that it finds the programs the config calls.
#
#   selfContained = true (default)   the package is everything: this config
#       (from the Nix store, read through $NVIM_CONFIG_ROOT) and its plugins
#       (the lazy-lock.json commits, nix/plugins.nix, through
#       $NVIM_PLUGIN_ROOT). Nothing is installed or downloaded when Neovim
#       runs; no home-manager, no clone in ~/.config needed -- `nix run`,
#       `nix profile install`, or a line in environment.systemPackages.
#       lazy.nvim only loads the plugins on first use (the fast start).
#       Update the plugins with `nix run .#update-plugins`, then rebuild.
#       It keeps its own data (history, parsers) under the name
#       `czernous-nvim` ($NVIM_APPNAME), apart from any ~/.config/nvim.
#   selfContained = false            only Neovim and the tools: the config is
#       your clone at ~/.config/nvim and lazy.nvim manages the plugins
#       (`:Lazy update`), as on a machine without Nix. For working on the config.
#
# Tools here are appended to $PATH (--suffix): a project's devshell, which is
# earlier on $PATH, always wins.
{
  lib,
  symlinkJoin,
  makeWrapper,
  neovim-unwrapped,
  plugins,
  configDir,
  selfContained ? true,
  git,
  ripgrep,
  fd,
  gcc,
  tree-sitter,
}:
let
  wrapperArgs =
    lib.optionals selfContained [
      "--set-default"
      "NVIM_APPNAME"
      "czernous-nvim"
      "--set-default"
      "NVIM_PLUGIN_ROOT"
      "${plugins}"
      "--set"
      "NVIM_CONFIG_ROOT"
      "${configDir}"
      "--add-flags"
      "--cmd 'set rtp^=${configDir}' -u ${configDir}/init.lua"
    ]
    ++ [
      "--suffix"
      "PATH"
      ":"
      (lib.makeBinPath [
        git # git change markers, :Git (and installing plugins when lazy.nvim manages them)
        ripgrep # searching inside files
        fd # finding files
        gcc # builds syntax-highlighting parsers...
        tree-sitter # ...together with this
      ])
    ];
in
symlinkJoin {
  name = "czernous-neovim-${neovim-unwrapped.version}";
  paths = [ neovim-unwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/nvim ${lib.escapeShellArgs wrapperArgs}
  '';
  meta.mainProgram = "nvim";
}
