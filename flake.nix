{
  # This Neovim config on Nix.
  #
  # The Lua config is the same files with or without Nix. Nix supplies the
  # prebuilt programs around it:
  #   * Neovim itself plus what the config calls (git, ripgrep, fd, a C compiler
  #     and the tree-sitter CLI for building syntax parsers): nix/package.nix;
  #   * per-language toolchains as devshells -- language server, formatter,
  #     linter and debugger for each stack, all prebuilt: nix/devshells.nix.
  # Plugins are managed by Nix too: fetched into the store at exactly the
  # lazy-lock.json commits (nix/plugins.nix), nothing downloaded at run time;
  # lazy.nvim only loads them on first use. `nix run .#update-plugins` is the
  # counterpart of `:Lazy update`: it moves lazy-lock.json to the newest commits
  # and shows what changed; a rebuild then fetches them. The package carries the
  # config as well, so it works by itself: home-manager is optional.
  # (packages.neovim-lazy is only Neovim + tools, for working on the config:
  # your clone at ~/.config/nvim, plugins managed by lazy.nvim.)
  # Colours: on a machine themed by Stylix the config follows Stylix's palette
  # file by itself (lua/czernous/theme.lua); nothing to set here.
  #
  #   nix develop .#go            Neovim + Go + gopls + delve (also rust, java, dotnet, web, lua, python)
  #   nix run github:czernous/nvim-cfg     try it: no install, no home-manager, no clone
  #   nix build .#neovim          Neovim with this config, the plugins and the basic tools
  #   nix run .#update-plugins    update the plugins (rewrites lazy-lock.json)
  #   homeManagerModules.default  programs.czernous-nvim.enable = true;
  #
  # NOT YET EVALUATED: written on a machine without Nix. Run `nix flake check`
  # and `nix build .#neovim` before relying on it (see docs/nix.md).
  #
  # No versions are named here: flake.lock pins nixpkgs (`nix flake update`
  # moves it); lazy-lock.json pins the plugins (`:Lazy update` moves it).
  description = "czernous Neovim config: plugins from lazy-lock.json, tools and devshells from nixpkgs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        plugins = pkgs.callPackage ./nix/plugins.nix { };
        # everything from the store: this config + plugins at the lazy-lock.json commits
        neovim = pkgs.callPackage ./nix/package.nix {
          inherit plugins;
          configDir = self;
        };
        # only Neovim + tools: your clone at ~/.config/nvim, plugins by lazy.nvim
        neovim-lazy = pkgs.callPackage ./nix/package.nix {
          inherit plugins;
          configDir = self;
          selfContained = false;
        };
        default = neovim;
        # `nix run .#update-plugins` in a clone: lazy-lock.json -> newest commits
        update-plugins = pkgs.writeShellApplication {
          name = "update-plugins";
          runtimeInputs = [
            pkgs.neovim-unwrapped
            pkgs.git
          ];
          text = ''
            if [ ! -f nix/update-plugins.lua ]; then
              echo "Run this in your clone of the Neovim config (the folder with lazy-lock.json)." >&2
              exit 1
            fi
            exec nvim -l nix/update-plugins.lua "$@"
          '';
        };
      });

      devShells = forAllSystems (
        pkgs:
        import ./nix/devshells.nix {
          inherit pkgs;
          neovim = self.packages.${pkgs.stdenv.hostPlatform.system}.neovim;
        }
      );

      homeManagerModules.default = import ./nix/home-manager.nix self;
    };
}
