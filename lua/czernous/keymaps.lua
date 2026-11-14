-- ============================================================================
-- ALL keymaps live in this file, grouped by purpose. To see, change or remove
-- a key, edit it here. Other files only *point* at this one.
--
-- Each entry: { mode, lhs, rhs, desc = '...', plugin = '...', expr = bool, remap = bool }
--   mode    "n" normal  "i" insert  "x" visual  "o" operator-pending
--           or a list like { "n", "x" }
--   lhs     the keys you press. <leader> = Space. <C-x> = Ctrl+x, <M-x> = Alt+x,
--           <S-x> = Shift+x, <CR> = Enter.
--   rhs     what happens: a command string or a Lua function
--   plugin  (optional) lazy.nvim plugin name; the key then loads that plugin on
--           first press (see M.lazy)
--   remap   (optional) the rhs is itself made of mapped keys (used to alias a
--           built-in key under another name)
--
-- Neovim's own keys are not repeated here. The ones worth knowing are listed
-- under BUILT-IN at the bottom of this comment; which-key shows them too.
--
-- Inside Neovim: press <leader> and wait for the popup, or <leader>pk to search
-- every key by what it does.
--
-- BUILT-IN (no configuration, work in any Neovim 0.12):
--   grn rename          gra code action (fixes)   grr references   gri implementation
--   grt type definition gO  outline of the file   ]d [d next/previous problem
--   ]q [q next/previous quickfix item             ]b [b next/previous buffer
--   gcc comment line    gc{motion} comment        <C-w>d problem under cursor
--   In visual mode: an = grow selection to the surrounding code, in = shrink it
--   In insert mode: <C-s> show the arguments of the function being called
-- ============================================================================

local M = {}

-- One cached function per telescope picker, so two keys calling the same picker
-- share the same function (lets the check report duplicate keys).
local pickers = {}
local function telescope(name, opts)
  local id = name .. vim.inspect(opts or {})
  pickers[id] = pickers[id] or function() require('telescope.builtin')[name](opts) end
  return pickers[id]
end

-- Telescope picker that searches the current file's project (see project.lua);
-- the window title shows which folder is searched.
local function in_project(name, title, extra)
  pickers[name .. ':project'] = pickers[name .. ':project'] or function()
    local root = require('czernous.project').root(0)
    local opts = vim.tbl_extend('force', { cwd = root, prompt_title = title .. ' in ' .. vim.fn.fnamemodify(root, ':~') }, extra and extra() or {})
    require('telescope.builtin')[name](opts)
  end
  return pickers[name .. ':project']
end

local function harpoon() return require('harpoon') end
local function gs() return require('gitsigns') end
local function ts_select(obj) return function() require('nvim-treesitter-textobjects.select').select_textobject(obj, 'textobjects') end end
local function ts_move(fn, obj) return function() require('nvim-treesitter-textobjects.move')[fn](obj, 'textobjects') end end

M.groups = {
  {
    -- <leader>p... : find things in the project of the file you are in
    name = 'Find',
    keys = {
      { 'n', '<leader>pf', in_project('find_files', 'Find files'), desc = "Find files (this file's project)" },
      { 'n', '<leader>pg', in_project('live_grep', 'Grep'), desc = "Grep as you type (this file's project)" },
      { 'n', '<leader>ps', in_project('grep_string', 'Search', function() return { search = vim.fn.input('Grep > ') } end), desc = "Search for a word (this file's project)" },
      { 'n', '<leader>pw', in_project('grep_string', 'Word under cursor'), desc = "Search for the word under the cursor (this file's project)" },
      { 'n', '<leader>pb', telescope('buffers'), desc = 'Find an open buffer' },
      { 'n', '<leader>pr', telescope('resume'), desc = 'Reopen the last search' },
      { 'n', '<leader>pk', telescope('keymaps'), desc = 'Search all keys by what they do' },
      { 'n', '<leader>ph', telescope('help_tags'), desc = 'Search the help' },
      { 'n', '<leader>?', telescope('oldfiles'), desc = 'Recently opened files' },
      { 'n', '<leader>/', function()
        require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown({ previewer = false }))
      end, desc = 'Search in this file' },
      -- The folder of the current file as an editable list: rename, move, delete
      -- files by editing lines, then :w. `-` goes up a folder, <CR> opens.
      { 'n', '<leader>pv', '<cmd>Oil<cr>', desc = 'Project view (folder as an editable list)' },
    },
  },
  {
    name = 'Harpoon (pinned files)',
    keys = {
      { 'n', '<leader>a', function() harpoon():list():add() end, desc = 'Harpoon: pin this file' },
      { 'n', '<C-e>', function() harpoon().ui:toggle_quick_menu(harpoon():list()) end, desc = 'Harpoon: menu' },
      { 'n', '<leader>1', function() harpoon():list():select(1) end, desc = 'Harpoon: file 1' },
      { 'n', '<leader>2', function() harpoon():list():select(2) end, desc = 'Harpoon: file 2' },
      { 'n', '<leader>3', function() harpoon():list():select(3) end, desc = 'Harpoon: file 3' },
      { 'n', '<leader>4', function() harpoon():list():select(4) end, desc = 'Harpoon: file 4' },
      { 'n', '<leader>[', function() harpoon():list():prev() end, desc = 'Harpoon: previous file' },
      { 'n', '<leader>]', function() harpoon():list():next() end, desc = 'Harpoon: next file' },
    },
  },
  {
    -- <leader>e... : errors, warnings and hints ("problems"), and fixing them
    name = 'Problems',
    keys = {
      { 'n', '<leader>ee', telescope('diagnostics', { bufnr = 0 }), desc = 'Problems in this file (list)' },
      { 'n', '<leader>ea', telescope('diagnostics'), desc = 'Problems in all open files (list)' },
      { 'n', '<leader>en', function() vim.diagnostic.jump({ count = 1 }) end, desc = 'Next problem (same as ]d)' },
      { 'n', '<leader>ep', function() vim.diagnostic.jump({ count = -1 }) end, desc = 'Previous problem (same as [d)' },
      { { 'n', 'x' }, '<leader>ef', function() vim.lsp.buf.code_action() end, desc = 'Fix: show the fixes offered here (same as gra)' },
      { 'n', '<leader>ed', function() vim.diagnostic.open_float() end, desc = 'Describe the problem under the cursor' },
      { 'n', '<leader>eq', function() vim.diagnostic.setqflist() end, desc = 'Send all problems to the quickfix list (]q / [q to step)' },
    },
  },
  {
    name = 'Code help',
    keys = {
      -- Works everywhere: says so when no language server is running for the file.
      -- Press K twice to jump into the popup (q closes it).
      { 'n', 'K', function() require('czernous.lsp').hover() end, desc = 'Documentation for what is under the cursor' },
    },
  },
  {
    name = 'Editing',
    keys = {
      { 'x', 'J', ":m '>+1<CR>gv=gv", desc = 'Move selection down' },
      { 'x', 'K', ":m '<-2<CR>gv=gv", desc = 'Move selection up' },
      { 'n', 'J', 'mzJ`z', desc = 'Join lines (cursor stays)' },
      { 'x', '<leader>p', [["_dP]], desc = 'Paste over selection (keep what was copied)' },
      { { 'n', 'x' }, '<leader>y', [["+y]], desc = 'Copy to the system clipboard' },
      { 'n', '<leader>Y', [["+Y]], desc = 'Copy the line to the system clipboard' },
      { { 'n', 'x' }, '<leader>d', [["_d]], desc = 'Delete without copying' },
      { 'n', '<leader>s', [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], desc = 'Replace the word under the cursor everywhere (live preview)' },
      { 'n', '<leader>f', function() require('czernous.format').format() end, desc = 'Format this file' },
      { 'n', '<leader>F', function() require('czernous.format').spotless() end, desc = 'Format with Spotless (exact; Gradle projects)' },
      { 'n', '<leader>x', '<cmd>!chmod +x %<CR>', desc = 'Make this file executable' },
      { 'n', '<leader><leader>', function()
        if vim.bo.filetype == 'lua' or vim.bo.filetype == 'vim' then
          vim.cmd('source %')
        else
          vim.notify('Nothing to source: not a Lua/Vim file', vim.log.levels.WARN)
        end
      end, desc = 'Run (source) this Lua/Vim file' },
      { 'n', '<leader>u', function()
        vim.cmd.packadd('nvim.undotree') -- ships with Neovim
        vim.cmd('Undotree')
      end, desc = 'Undo history (tree)' },
      -- Select by code structure. These are Neovim's own `an` / `in` under easier keys.
      { 'n', '<C-space>', 'van', remap = true, desc = 'Select the code under the cursor' },
      { 'x', '<C-space>', 'an', remap = true, desc = 'Grow the selection' },
      { 'x', '<M-space>', 'in', remap = true, desc = 'Shrink the selection' },
    },
  },
  {
    name = 'Moving around',
    keys = {
      { 'n', '<C-d>', '<C-d>zz', desc = 'Half page down (cursor stays centred)' },
      { 'n', '<C-u>', '<C-u>zz', desc = 'Half page up (cursor stays centred)' },
      { 'n', 'n', 'nzzzv', desc = 'Next search match (centred)' },
      { 'n', 'N', 'Nzzzv', desc = 'Previous search match (centred)' },
      { 'n', 'k', "v:count == 0 ? 'gk' : 'k'", expr = true, desc = 'Up (by screen line when text wraps)' },
      { 'n', 'j', "v:count == 0 ? 'gj' : 'j'", expr = true, desc = 'Down (by screen line when text wraps)' },
    },
  },
  {
    name = 'Git',
    keys = {
      { 'n', '<leader>gs', '<cmd>Git<cr>', desc = 'Git status (stage, commit, push...)' },
    },
  },
  {
    name = 'Toggles',
    keys = {
      { 'n', '<leader>tT', function() require('czernous.theme').toggle_transparency() end, desc = 'Toggle the transparent background' },
    },
  },
  {
    -- Text objects: use after an operator or in visual mode, e.g. `daf`
    -- deletes a function, `vic` selects inside a class, `cia` changes an argument.
    name = 'Code structure',
    keys = {
      { { 'x', 'o' }, 'af', ts_select('@function.outer'), desc = 'a function' },
      { { 'x', 'o' }, 'if', ts_select('@function.inner'), desc = 'inside a function' },
      { { 'x', 'o' }, 'ac', ts_select('@class.outer'), desc = 'a class' },
      { { 'x', 'o' }, 'ic', ts_select('@class.inner'), desc = 'inside a class' },
      { { 'x', 'o' }, 'aa', ts_select('@parameter.outer'), desc = 'an argument' },
      { { 'x', 'o' }, 'ia', ts_select('@parameter.inner'), desc = 'inside an argument' },
      { { 'n', 'x', 'o' }, ']m', ts_move('goto_next_start', '@function.outer'), desc = 'Next function' },
      { { 'n', 'x', 'o' }, ']]', ts_move('goto_next_start', '@class.outer'), desc = 'Next class' },
      { { 'n', 'x', 'o' }, ']M', ts_move('goto_next_end', '@function.outer'), desc = 'End of next function' },
      { { 'n', 'x', 'o' }, '][', ts_move('goto_next_end', '@class.outer'), desc = 'End of next class' },
      { { 'n', 'x', 'o' }, '[m', ts_move('goto_previous_start', '@function.outer'), desc = 'Previous function' },
      { { 'n', 'x', 'o' }, '[[', ts_move('goto_previous_start', '@class.outer'), desc = 'Previous class' },
      { { 'n', 'x', 'o' }, '[M', ts_move('goto_previous_end', '@function.outer'), desc = 'End of previous function' },
      { { 'n', 'x', 'o' }, '[]', ts_move('goto_previous_end', '@class.outer'), desc = 'End of previous class' },
      { 'n', '<leader>cn', function() require('nvim-treesitter-textobjects.swap').swap_next('@parameter.inner') end, desc = 'Swap this argument with the next' },
      { 'n', '<leader>cp', function() require('nvim-treesitter-textobjects.swap').swap_previous('@parameter.inner') end, desc = 'Swap this argument with the previous' },
    },
  },
  {
    -- Only in buffers where a language server is attached (see M.lsp). The rest
    -- of the language keys are Neovim's built-ins (grn, gra, gri, grt... above).
    name = 'Language server',
    buffer = 'lsp',
    keys = {
      { 'n', 'gd', telescope('lsp_definitions'), desc = 'Go to definition' },
      { 'n', 'gD', function() vim.lsp.buf.declaration() end, desc = 'Go to declaration' },
      { 'n', 'grr', telescope('lsp_references'), desc = 'Where is this used? (references)' },
      { 'n', 'gO', telescope('lsp_document_symbols'), desc = 'Outline of this file' },
      { 'n', '<leader>ws', telescope('lsp_dynamic_workspace_symbols'), desc = 'Find a symbol in the whole project' },
      { 'n', '<leader>rn', function() vim.lsp.buf.rename() end, desc = 'Rename (same as grn)' },
      { 'n', '<leader>ca', function() vim.lsp.buf.code_action() end, desc = 'Code action / fix (same as gra)' },
    },
  },
  {
    -- Only in buffers inside a git repo (see M.gitsigns).
    name = 'Git changes',
    buffer = 'gitsigns',
    keys = {
      { { 'n', 'x' }, ']c', function()
        if vim.wo.diff then return ']c' end
        vim.schedule(function() gs().nav_hunk('next') end)
        return '<Ignore>'
      end, expr = true, desc = 'Next change' },
      { { 'n', 'x' }, '[c', function()
        if vim.wo.diff then return '[c' end
        vim.schedule(function() gs().nav_hunk('prev') end)
        return '<Ignore>'
      end, expr = true, desc = 'Previous change' },
      { 'x', '<leader>hs', function() gs().stage_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, desc = 'Stage the selected lines' },
      { 'x', '<leader>hr', function() gs().reset_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, desc = 'Undo the change in the selected lines' },
      { 'n', '<leader>hs', function() gs().stage_hunk() end, desc = 'Stage / unstage this change' },
      { 'n', '<leader>hr', function() gs().reset_hunk() end, desc = 'Undo this change' },
      { 'n', '<leader>hS', function() gs().stage_buffer() end, desc = 'Stage the whole file' },
      { 'n', '<leader>hR', function() gs().reset_buffer() end, desc = 'Undo all changes in the file' },
      { 'n', '<leader>hp', function() gs().preview_hunk() end, desc = 'Preview this change' },
      { 'n', '<leader>hi', function() gs().preview_hunk_inline() end, desc = 'Show this change inline (with deleted lines)' },
      { 'n', '<leader>hb', function() gs().blame_line({ full = false }) end, desc = 'Who changed this line?' },
      { 'n', '<leader>hd', function() gs().diffthis() end, desc = 'Diff against the staged version' },
      { 'n', '<leader>hD', function() gs().diffthis('~') end, desc = 'Diff against the last commit' },
      { 'n', '<leader>tb', function() gs().toggle_current_line_blame() end, desc = 'Toggle "who changed this line" as you move' },
      { { 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>', desc = 'inside a change' },
    },
  },
}

-- Labels shown by which-key for key prefixes. (A check fails if a label's prefix
-- has no keys, so this list can't go stale.)
M.prefixes = {
  { '<leader>p', group = 'Find' },
  { '<leader>e', group = 'Problems (errors, fixes)' },
  { '<leader>h', group = 'Git change' },
  { '<leader>h', group = 'Git change', mode = 'x' },
  { '<leader>g', group = 'Git' },
  { '<leader>t', group = 'Toggle' },
  { '<leader>c', group = 'Code' },
  { '<leader>r', group = 'Rename' },
  { '<leader>w', group = 'Whole project' },
  { 'gr', group = 'Language server (built-in)' },
}

local function set(key, extra)
  local opts = vim.tbl_extend('force', { desc = key.desc, expr = key.expr, remap = key.remap, silent = key.expr or nil }, extra or {})
  vim.keymap.set(key[1], key[2], key[3], opts)
end

--- Set every global key that doesn't belong to a lazily-loaded plugin.
function M.setup()
  for _, g in ipairs(M.groups) do
    if not g.buffer then
      for _, key in ipairs(g.keys) do
        if not key.plugin then set(key) end
      end
    end
  end
end

--- lazy.nvim `keys` spec for one plugin: `keys = require('czernous.keymaps').lazy('some-plugin')`.
---@param plugin string
function M.lazy(plugin)
  local out = {}
  for _, g in ipairs(M.groups) do
    for _, key in ipairs(g.keys) do
      if key.plugin == plugin then
        out[#out + 1] = { key[2], key[3], mode = key[1], desc = key.desc, expr = key.expr }
      end
    end
  end
  return out
end

local function set_buffer_group(name, bufnr)
  for _, g in ipairs(M.groups) do
    if g.buffer == name then
      for _, key in ipairs(g.keys) do set(key, { buffer = bufnr }) end
    end
  end
end

--- Buffer-local language-server keys (called on LspAttach).
function M.lsp(bufnr) set_buffer_group('lsp', bufnr) end

--- Buffer-local git keys (called from gitsigns on_attach).
function M.gitsigns(bufnr) set_buffer_group('gitsigns', bufnr) end

--- which-key `spec`: a copy of the group labels above. A copy, because which-key
--- empties the table it is given.
function M.which_key() return vim.deepcopy(M.prefixes) end

--- Flat list of every key: { mode, lhs, desc, group }.
function M.all()
  local out = {}
  for _, g in ipairs(M.groups) do
    for _, key in ipairs(g.keys) do
      for _, m in ipairs(type(key[1]) == 'table' and key[1] or { key[1] }) do
        out[#out + 1] = { mode = m, lhs = key[2], desc = key.desc, group = g.name }
      end
    end
  end
  return out
end

return M
