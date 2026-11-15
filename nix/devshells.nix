# One shell per stack: everything the editor uses for that language -- the
# toolchain, the language server (completion, errors, go-to-definition), the
# formatter / linter, and the debugger (<leader>b). `nix develop .#go`, or from
# a project: `use flake github:czernous/nvim-cfg#go` in its .envrc.
#
# A project with its own devshell does not need these: the config only looks
# at $PATH. They are here so a new machine (or a colleague's) works at once.
# No versions are named: each attribute is nixpkgs' current default.
{ pkgs, neovim }:
let
  shell =
    name: packages:
    pkgs.mkShell {
      name = "nvim-${name}";
      packages = [ neovim ] ++ packages;
    };
in
{
  # just the editor and its basic tools
  default = shell "base" [ ];

  go = shell "go" (
    with pkgs;
    [
      go
      gopls # language server (runs staticcheck's lints too)
      delve # debugger: dlv
    ]
  );

  rust = shell "rust" (
    with pkgs;
    [
      cargo
      rustc
      rust-analyzer
      clippy # lints, shown as you save
      rustfmt
      lldb # debugger: lldb-dap
      mold # fast linker; a project opts in (docs/nix.md)
    ]
  );

  cpp = shell "cpp" (
    with pkgs;
    [
      clang
      clang-tools # clangd (language server), clang-format, clang-tidy
      cmake
      ninja
      lldb # debugger: lldb-dap
      mold # fast linker; a project opts in (docs/nix.md)
    ]
  );

  java = shell "java" (
    with pkgs;
    [
      jdk
      jdt-language-server # jdtls
      kotlin-language-server
    ]
  );

  dotnet = shell "dotnet" (
    with pkgs;
    [
      dotnet-sdk
      csharp-ls
      netcoredbg # debugger
    ]
  );

  web = shell "web" (
    with pkgs;
    [
      bun
      biome # formatter + linter
      vtsls # TypeScript language server
    ]
  );

  lua = shell "lua" (
    with pkgs;
    [
      lua-language-server
      stylua
    ]
  );

  python = shell "python" (
    with pkgs;
    [
      python3
      ruff # formatter + linter
    ]
  );
}
