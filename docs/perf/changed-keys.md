# Changed keys (stage 2a)

Find any key from inside Neovim: `<leader>pk` (search keys by what they do), or press
`<leader>` and wait.

## New

| Key | Does |
|---|---|
| `<leader>ee` / `<leader>ea` | list the problems (errors, warnings, hints) in this file / in all open files |
| `<leader>en` / `<leader>ep` | jump to the next / previous problem and show its message (same as `]d` / `[d`) |
| `<leader>ef` | show the fixes offered at the cursor (same as `gra`) |
| `<leader>ed` | describe the problem under the cursor |
| `<leader>eq` | send all problems to the quickfix list (`]q` / `[q` step through it) |
| `<leader>F` | format with Spotless, exact (Gradle projects that use it) |
| `<leader>pk` | search all keys by what they do |
| `<leader>pr` | reopen the last search |
| `<leader>pw` | search the project for the word under the cursor |
| `<leader>hi` | show a git change inline, with the deleted lines |

## Changed

| Key | Before | Now | Why |
|---|---|---|---|
| `<leader>f` | LSP format / Neoformat; Spotless (~1 s) in Gradle projects | the project's formatter program if on `$PATH`, else the language server: always instant | Spotless via Gradle felt slow |
| `K` | LSP hover; silent with no language server | documentation, or a message saying no server is running | failed silently |
| `<leader>pv` | built-in file explorer | the folder as an editable list (oil.nvim): edit lines to rename/move/delete, `:w` applies, `-` goes up, `q` closes | better, faster explorer |
| `<leader>y`, `<leader>d` | normal mode only | also on a visual selection | the usual way to use them |
| `<leader>u` | undotree plugin | Neovim's built-in undo tree | one plugin fewer |
| `<C-space>` / `<M-space>` | own selection code | Neovim's built-in `an` / `in` (select code, grow, shrink) | built-in first |
| `<leader>td` | "toggle" that only previewed | `<leader>hi` | name matched what it did |

## Removed (use the built-in key)

| Removed | Use instead |
|---|---|
| `<C-k>` / `<C-j>` (quickfix next/previous, reversed) | `]q` / `[q` |
| `<leader>k` / `<leader>j` (location list) | `]l` / `[l` |
| `<leader>vd` | `<leader>ed` or `<C-w>d` |
| `gI`, `<leader>D` | `gri` (implementation), `grt` (type definition) |
| `<C-h>` in insert mode | `<C-s>` (argument help; it also appears by itself while typing a call) |
| `Y` remap | nothing: Neovim's `Y` already copies to the end of the line |
| `<leader>wa` / `<leader>wr` / `<leader>wl` (workspace folders) | rarely needed; `:lua vim.lsp.buf.add_workspace_folder()` etc. |
| `<leader>tt…` (Trouble) | `<leader>e…` above |
| `<leader>nf` (Neoformat) | `<leader>f` |
