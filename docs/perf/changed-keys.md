# Changed keys (stage 2a)

Find any key from inside Neovim: `<leader>pk` (search keys by what they do), or press
`<leader>` and wait.

## New

| Key | Does |
|---|---|
| `<leader>ee` / `<leader>ea` | list the problems (errors, warnings, hints) in this file / in all open files |
| `<leader>en` / `<leader>ep` | jump to the next / previous problem and show its message (same as `]d` / `[d`) |
| `<leader>ef` | list the fixes offered at the cursor, each with a preview of what it changes (also `gra`, `<leader>ca`). The statusline shows `fix` when the line under the cursor has one |
| `<leader>b…` | debugging: `bb` breakpoint, `bB` conditional breakpoint, `bc` start / continue, `bn` next line, `bi` step into, `bo` step out, `bv` variables, `bs` call stack, `be` value under the cursor, `br` console, `bl` run the last session again, `bq` stop. Needs the language's debugger on `$PATH` (`dlv`, `lldb-dap` or `codelldb`, `netcoredbg`) |
| `gm` in the explorer | move / rename by typing the destination path, like `mv` (folders are created; a folder as destination means "into it") |
| `<leader>tg` | switch the explorer's git status letters off / on (two letters after a name, as `git status --short` prints them: staged, then unstaged; `?` new, `!` ignored). Explorer first open measured 20-33 ms with it, 22-29 ms without |
| `<leader>ttx` / `<leader>ttd` / `<leader>ttq` / `<leader>ttr` | the keys Trouble used, kept as aliases: problems in all files / in this file / fixes here / where is this used |
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
| `K` | LSP hover; in files with no language server, Vim's own lookup (man page) or nothing | documentation; if no server is attached: Vim's own lookup in help/shell/C/make files, otherwise a message saying no server is running (or that it is still starting) | failed silently in e.g. Kotlin files |
| `<leader>pv` | built-in file explorer | the folder as an editable list (oil.nvim), with a hint bar: `Enter` open, `-` up, `q` close; edit a line + `:w` to rename/move, `dd` + `:w` to delete, `o` + a name + `:w` for a new file | measured: first open 34 ms vs 693 ms for the built-in one on this machine |
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
| `<leader>q` (problems to the location list) | `<leader>eq` (problems to the quickfix list) |
| `gI`, `<leader>D` | `gri` (implementation), `grt` (type definition) |
| `<C-h>` in insert mode | `<C-s>` (argument help; it also appears by itself while typing a call) |
| `Y` remap | nothing: Neovim's `Y` already copies to the end of the line |
| `<leader>wa` / `<leader>wr` / `<leader>wl` (workspace folders) | rarely needed; `:lua vim.lsp.buf.add_workspace_folder()` etc. |
| Trouble (the plugin) | `<leader>e…` above; `<leader>ttx/ttd/ttq/ttr` still work as aliases |
| `<leader>nf` (Neoformat) | `<leader>f` |
