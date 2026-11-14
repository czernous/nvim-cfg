-- [[ nvim-treesitter -- main branch ]]
-- The master-branch module system (require('nvim-treesitter.configs').setup)
-- is gone. On main, highlighting/indent are provided by Neovim core and wired
-- up manually here; parsers are installed via require('nvim-treesitter').install.

local ts = require('nvim-treesitter')

-- Parsers to keep installed (installs to stdpath('data')/site/parser).
local ensure_installed = {
  'bash', 'c', 'cpp', 'diff', 'html', 'javascript', 'jsdoc', 'json',
  'lua', 'luadoc', 'luap', 'markdown', 'markdown_inline', 'python', 'query',
  'regex', 'toml', 'tsx', 'typescript', 'vim', 'vimdoc', 'yaml', 'sql',
  'c_sharp', 'rust', 'go',
}

-- Install only the ones that are missing (install() is async; no-op if present).
local installed = ts.get_installed()
local missing = vim.tbl_filter(function(lang)
  return not vim.tbl_contains(installed, lang)
end, ensure_installed)
if #missing > 0 then
  ts.install(missing)
end

-- Enable treesitter highlighting + indentation per buffer.
-- See `:h treesitter-highlight`. vim.treesitter.start() infers the language
-- from the buffer's filetype and no-ops (via pcall) when no parser exists.
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('czernous_treesitter', { clear = true }),
  callback = function(ev)
    if pcall(vim.treesitter.start, ev.buf) then
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

-- [[ Text objects (nvim-treesitter-textobjects, main branch) ]]
require('nvim-treesitter-textobjects').setup({
  select = { lookahead = true },
  move = { set_jumps = true },
})

local select = require('nvim-treesitter-textobjects.select')
local move = require('nvim-treesitter-textobjects.move')
local swap = require('nvim-treesitter-textobjects.swap')

-- Selection text objects. Use in visual (x) or after an operator (o):
-- e.g. `vaf` visually select a function, `dif` delete inside a function,
-- `cia` change inside a parameter/argument. `a` = around, `i` = inner.
-- (Capture groups come from the textobjects queries; see `:h treesitter-textobjects`.)
vim.keymap.set({ 'x', 'o' }, 'af', function() select.select_textobject('@function.outer', 'textobjects') end, { desc = 'a function' })
vim.keymap.set({ 'x', 'o' }, 'if', function() select.select_textobject('@function.inner', 'textobjects') end, { desc = 'inner function' })
vim.keymap.set({ 'x', 'o' }, 'ac', function() select.select_textobject('@class.outer', 'textobjects') end, { desc = 'a class' })
vim.keymap.set({ 'x', 'o' }, 'ic', function() select.select_textobject('@class.inner', 'textobjects') end, { desc = 'inner class' })
vim.keymap.set({ 'x', 'o' }, 'aa', function() select.select_textobject('@parameter.outer', 'textobjects') end, { desc = 'a parameter/argument' })
vim.keymap.set({ 'x', 'o' }, 'ia', function() select.select_textobject('@parameter.inner', 'textobjects') end, { desc = 'inner parameter/argument' })

-- Movement (normal/visual/operator-pending). `]` = next, `[` = previous;
-- `m`/`M` = function start/end, `]]`/`][` etc. = class start/end.
-- e.g. `]m` jump to next function, `[[` jump to previous class.
vim.keymap.set({ 'n', 'x', 'o' }, ']m', function() move.goto_next_start('@function.outer', 'textobjects') end, { desc = 'Next function start' })
vim.keymap.set({ 'n', 'x', 'o' }, ']]', function() move.goto_next_start('@class.outer', 'textobjects') end, { desc = 'Next class start' })
vim.keymap.set({ 'n', 'x', 'o' }, ']M', function() move.goto_next_end('@function.outer', 'textobjects') end, { desc = 'Next function end' })
vim.keymap.set({ 'n', 'x', 'o' }, '][', function() move.goto_next_end('@class.outer', 'textobjects') end, { desc = 'Next class end' })
vim.keymap.set({ 'n', 'x', 'o' }, '[m', function() move.goto_previous_start('@function.outer', 'textobjects') end, { desc = 'Prev function start' })
vim.keymap.set({ 'n', 'x', 'o' }, '[[', function() move.goto_previous_start('@class.outer', 'textobjects') end, { desc = 'Prev class start' })
vim.keymap.set({ 'n', 'x', 'o' }, '[M', function() move.goto_previous_end('@function.outer', 'textobjects') end, { desc = 'Prev function end' })
vim.keymap.set({ 'n', 'x', 'o' }, '[]', function() move.goto_previous_end('@class.outer', 'textobjects') end, { desc = 'Prev class end' })

-- Swap the parameter/argument under the cursor with the next/previous one.
vim.keymap.set('n', '<leader>swn', function() swap.swap_next('@parameter.inner') end, { desc = 'TS swap next parameter' })
vim.keymap.set('n', '<leader>swp', function() swap.swap_previous('@parameter.inner') end, { desc = 'TS swap previous parameter' })

-- [[ Incremental selection ]]
-- The master `incremental_selection` module was removed on main; this is a
-- compact reimplementation over treesitter nodes.
do
  local selections = {} -- per-buffer stack of nodes

  local function select_node(node)
    local srow, scol, erow, ecol = node:range()
    vim.api.nvim_win_set_cursor(0, { srow + 1, scol })
    vim.cmd('normal! v')
    if ecol == 0 then -- range end is exclusive; step back to previous line's end
      vim.api.nvim_win_set_cursor(0, { erow, 0 })
      vim.cmd('normal! $')
    else
      vim.api.nvim_win_set_cursor(0, { erow + 1, ecol - 1 })
    end
  end

  local function ranges_equal(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
  end

  local function init_selection()
    local buf = vim.api.nvim_get_current_buf()
    local node = vim.treesitter.get_node()
    if not node then return end
    selections[buf] = { node }
    select_node(node)
  end

  local function node_incremental()
    local buf = vim.api.nvim_get_current_buf()
    local stack = selections[buf]
    if not stack or #stack == 0 then return init_selection() end
    local cur = stack[#stack]
    local parent = cur:parent()
    while parent and ranges_equal({ parent:range() }, { cur:range() }) do
      parent = parent:parent()
    end
    if parent then
      table.insert(stack, parent)
      select_node(parent)
    else
      select_node(cur)
    end
  end

  local function node_decremental()
    local buf = vim.api.nvim_get_current_buf()
    local stack = selections[buf]
    if not stack or #stack <= 1 then return end
    table.remove(stack)
    select_node(stack[#stack])
  end

  -- <c-space> = Ctrl+Space, <M-space> = Alt+Space (see the notation cheat-sheet
  -- at the top of remap.lua). Usage: in normal mode press Ctrl+Space to select
  -- the smallest node under the cursor; press it again (now in visual mode) to
  -- grow the selection to the enclosing node; Alt+Space shrinks it back.
  vim.keymap.set('n', '<c-space>', init_selection, { desc = 'TS init selection' })
  vim.keymap.set('x', '<c-space>', node_incremental, { desc = 'TS increment node' })
  vim.keymap.set('x', '<M-space>', node_decremental, { desc = 'TS decrement node' })
end
