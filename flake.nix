{
  # This Neovim config on Nix.
  #
  # The Lua config is the same files with or without Nix. Nix supplies the
  # prebuilt programs around it:
  #   * Neovim itself plus what the config calls (git, ripgrep, fd, a C compiler
  #     and the tree-sitter CLI for building syntax parsers): nix/package.nix;
  #   * per-language toolchains as devshells -- language server, formatter,
  #     linter and debugger for each stack, all prebuilt: nix/devshells.nix.
  # Plugins stay with lazy.nvim by default, so `:Lazy update` works as on any
  # machine. Optionally they are pinned into the Nix store at the lazy-lock.json
  # commits (packages.neovim-pinned, nix/plugins.nix): nothing is downloaded at
  # run time, and lazy.nvim only does the loading.
  # Colours: on a machine themed by Stylix the config follows Stylix's palette
  # file by itself (lua/czernous/theme.lua); nothing to set here.
  #
  #   nix develop .#go            Neovim + Go + gopls + delve (also rust, java, dotnet, web, lua, python)
  #   nix build .#neovim          Neovim with the basic tools
  #   nix build .#neovim-pinned   ...and the plugins from the store
  #   homeManagerModules.default  programs.czernous-nvim.enable = true;
  #
  # NOT YET EVALUATED: written on a machine without Nix. Run `nix flake check`
  # and `nix build .#neovim-pinned` before relying on it (see docs/nix.md).
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
        # plugins managed by lazy.nvim, as on any machine (`:Lazy update` works)
        neovim = pkgs.callPackage ./nix/package.nix { inherit plugins; };
        # plugins from the Nix store, at the lazy-lock.json commits
        neovim-pinned = pkgs.callPackage ./nix/package.nix {
          inherit plugins;
          pinPlugins = true;
        };
        default = neovim;
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
