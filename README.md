# czernous — Neovim config

Personal Neovim configuration (lazy.nvim + Mason-managed LSP).

## Supported Neovim versions

| Version | Status |
|---------|--------|
| **≥ 0.12.0** | ✅ Supported (minimum) |
| 0.12.x | ✅ Tested (developed on 0.12.4) |
| ≤ 0.11.x | ❌ Not supported |

**Why 0.12 is the floor** — two independent requirements:

- **nvim-treesitter `main` branch** requires Neovim **0.12+**. (The old `master`
  branch is archived and crashes on Neovim 0.11+ language injections, e.g.
  markdown code fences, so it is not an option.)
- LSP setup uses `vim.lsp.config()`/`vim.lsp.enable()` (0.11+),
  `vim.diagnostic.jump()` (0.11+), and `mason-lspconfig` v2 `automatic_enable`.

On 0.11 or older, treesitter startup will error. Any install method (distro
package, AppImage, build-from-source) is fine **as long as it is ≥ 0.12**.

## External dependencies

The Lua config is OS-agnostic. These live outside the config and must be present
on each machine:

| Dependency | Needed for | Debian/Ubuntu | Arch |
|-----------|-----------|---------------|------|
| C compiler (gcc/clang) | Compiling nvim-treesitter parsers | `apt install build-essential` (or `clang`) | `pacman -S base-devel` (or `clang`) |
| `tree-sitter` CLI ≥ 0.26.1 | Building parsers on the treesitter `main` branch (must be on `$PATH`) | `cargo install tree-sitter-cli` | `pacman -S tree-sitter-cli` |
| `tar`, `curl` | Parser downloads | usually present | usually present |
| `git` | lazy.nvim + Mason downloads | usually present | usually present |
| `ripgrep`, `fd` | Telescope live-grep / find (recommended) | `apt install ripgrep fd-find` | `pacman -S ripgrep fd` |
| `leptosfmt` | Rust + Leptos formatting (rust_analyzer config) | `cargo install leptosfmt` | `cargo install leptosfmt` |

LSP servers themselves (gopls, lua_ls, …) are downloaded by **Mason** as prebuilt
binaries into `~/.local/share/nvim/mason/` — no manual install needed.

## Adding a language

No code required — install the server and it auto-attaches with all keymaps:

```
:MasonInstall gopls        " or any lspconfig server name
```

Servers in `ensure_installed` (`cfg/lsp-config.lua`) are installed automatically
on first launch. Add explicit `vim.lsp.config('<server>', {...})` blocks there
**only** for special settings or language extensions (see `lua_ls`, `rust_analyzer`).

## Moving to another machine

Sync **only** `~/.config/nvim`. Do **not** copy `~/.local/share/nvim/` — let each
machine rebuild parsers and Mason binaries natively. On the new machine:

```
:Lazy restore     " installs the exact plugin commits pinned in lazy-lock.json
:TSUpdate         " compile treesitter parsers (needs a C compiler + tree-sitter CLI)
```

Parsers listed in `cfg/treesitter-config.lua` (`ensure_installed`) are also
installed automatically on first launch, provided the `tree-sitter` CLI is on
`$PATH`. If launching Neovim from a GUI/desktop entry that doesn't inherit your
shell `$PATH`, ensure `~/.cargo/bin` (or wherever `tree-sitter` lives) is on it.
