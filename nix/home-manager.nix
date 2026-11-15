# home-manager module -- a convenience, not a requirement: the package works
# by itself (see docs/nix.md for use without home-manager).
#
#   imports = [ inputs.nvim-cfg.homeManagerModules.default ];
#   programs.czernous-nvim.enable = true;
#
# Installs the self-contained package: config and plugins from the Nix store,
# nothing installed or downloaded when Neovim runs. Updating plugins:
# `nix run .#update-plugins` in a clone, commit lazy-lock.json, rebuild.
#
# To work on the config itself (your clone at ~/.config/nvim, lazy.nvim
# managing the plugins, `:Lazy update`):
#   programs.czernous-nvim.selfContained = false;
#
# Colours: nothing to configure. With Stylix enabled, Stylix writes
# ~/.config/stylix/palette.json and the config follows it (theme.lua); change
# the system theme and Neovim changes on its next start. Stylix's own Neovim
# target is not involved (it themes `programs.neovim`, which this does not use).
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.czernous-nvim;
  packages = self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.programs.czernous-nvim = {
    enable = lib.mkEnableOption "the czernous Neovim config";
    selfContained = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Config and plugins from the Nix store. false: only Neovim and tools; your clone at ~/.config/nvim, plugins managed by lazy.nvim.";
    };
    defaultEditor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set EDITOR and VISUAL to nvim.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ (if cfg.selfContained then packages.neovim else packages.neovim-lazy) ];
    home.sessionVariables = lib.mkIf cfg.defaultEditor {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };
}
