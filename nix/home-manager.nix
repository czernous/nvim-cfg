# home-manager module: installs the wrapped Neovim.
#
#   imports = [ inputs.nvim-cfg.homeManagerModules.default ];
#   programs.czernous-nvim.enable = true;
#
# By default it works like any machine, with prebuilt tools: you keep a clone
# of this repository at ~/.config/nvim, lazy.nvim installs the plugins, and
# `:Lazy update` updates them (commit the changed lazy-lock.json).
#
# For a machine that should be fully reproducible instead:
#   programs.czernous-nvim.pinPlugins = true;   # plugins from the Nix store
#   programs.czernous-nvim.linkConfig = true;   # ~/.config/nvim -> this flake (read-only)
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
    pinPlugins = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Take the plugins from the Nix store (the lazy-lock.json commits) instead of letting lazy.nvim install and update them.";
    };
    linkConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Link ~/.config/nvim to this flake's (read-only) copy of the config instead of using your own clone. Needs pinPlugins.";
    };
    defaultEditor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set EDITOR and VISUAL to nvim.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.linkConfig -> cfg.pinPlugins;
        message = "programs.czernous-nvim.linkConfig needs pinPlugins = true: lazy.nvim cannot write lazy-lock.json into a read-only config.";
      }
    ];
    home.packages = [ (if cfg.pinPlugins then packages.neovim-pinned else packages.neovim) ];
    xdg.configFile."nvim" = lib.mkIf cfg.linkConfig { source = self; };
    home.sessionVariables = lib.mkIf cfg.defaultEditor {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };
}
