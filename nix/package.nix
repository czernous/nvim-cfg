# Neovim, wrapped so that it finds the programs the config calls. It does NOT
# carry the config: that stays at ~/.config/nvim, so the same Neovim behaves
# the same as on a machine without Nix.
#
# Plugins, two ways:
#   pinPlugins = false (default)  lazy.nvim manages them as on any machine:
#       first start installs the commits in lazy-lock.json, `:Lazy update`
#       updates them and rewrites lazy-lock.json in your clone of the config.
#   pinPlugins = true             they come from the Nix store, at exactly the
#       lazy-lock.json commits (nix/plugins.nix): no network at run time,
#       identical on every machine; `:Lazy update` is then not available --
#       update on an unpinned machine, commit lazy-lock.json, rebuild.
# Either way lazy.nvim still does the loading on first use (the fast start).
#
# Tools here are appended to $PATH (--suffix): a project's devshell, which is
# earlier on $PATH, always wins.
{
  lib,
  symlinkJoin,
  makeWrapper,
  neovim-unwrapped,
  plugins,
  pinPlugins ? false,
  git,
  ripgrep,
  fd,
  gcc,
  tree-sitter,
}:
symlinkJoin {
  name = "czernous-neovim-${neovim-unwrapped.version}";
  paths = [ neovim-unwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/nvim \
      ${lib.optionalString pinPlugins "--set-default NVIM_PLUGIN_ROOT ${plugins}"} \
      --suffix PATH : ${
        lib.makeBinPath [
          git # installing plugins, git change markers, :Git
          ripgrep # searching inside files
          fd # finding files
          gcc # builds syntax-highlighting parsers...
          tree-sitter # ...together with this
        ]
      }
  '';
  meta.mainProgram = "nvim";
}
