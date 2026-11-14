-- ============================================================================
-- ALL keymaps live in this file, grouped by purpose. To see, change or remove
-- a key, edit it here. Other files only *point* at this one.
--
-- Each entry: { mode, lhs, rhs, desc = '...', plugin = '...', expr = bool }
--   mode    "n" normal  "i" insert  "v" visual+select  "x" visual  "o" operator-pending
--           or a list like { "n", "x" }
--   lhs     the keys you press. <leader> = Space. <C-x> = Ctrl+x, <M-x> = Alt+x,
--           <S-x> = Shift+x, <CR> = Enter.
--   rhs     what happens: a command string or a Lua function
--   plugin  (optional) lazy.nvim plugin name; the key then loads that plugin on
--           first press (see M.lazy)
--
-- Tips inside Neovim: press <leader> and wait for the which-key popup, or run
-- `:Telescope keymaps` to search all keys by description.
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

-- After jumping to a diagnostic, show its message in a popup.
-- (`jump({ float = true })` is deprecated and removed in Neovim 0.14.)
local function show_diagnostic(_, bufnr)
  vim.diagnostic.open_float({ bufnr = bufnr, scope = 'cursor', focus = false })
end

local function harpoon() return require('harpoon') end
local function gs() return require('gitsigns') end
local function ts_select(obj) return function() require('nvim-treesitter-textobjects.select').select_textobject(obj, 'textobjects') end end
local function ts_move(fn, obj) return function() require('nvim-treesitter-textobjects.move')[fn](obj, 'textobjects') end end

M.groups = {
  {
    name = 'Files & search',
    keys = {
      { 'n', '<leader>pv', '<cmd>Ex<cr>', desc = 'Project view (file explorer)' },
      { 'n', '<leader>pf', in_project('find_files', 'Find files'), desc = "Find files (this file's project)" },
      { 'n', '<leader>pg', in_project('live_grep', 'Grep'), desc = "Grep as you type (this file's project)" },
      { 'n', '<leader>ps', in_project('grep_string', 'Search', function() return { search = vim.fn.input('Grep > ') } end), desc = "Search for a word (this file's project)" },
      { 'n', '<leader>pb', telescope('buffers'), desc = 'Find open buffer' },
      { 'n', '<leader>ph', telescope('help_tags'), desc = 'Find help' },
      { 'n', '<leader>?', telescope('oldfiles'), desc = 'Recently opened files' },
      { 'n', '<leader>/', function()
        require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown({ winblend = 10, previewer = false }))
      end, desc = 'Search in current buffer' },
    },
  },
  {
    name = 'Harpoon (pinned files)',
    keys = {
      { 'n', '<leader>a', function() harpoon():list():add() end, desc = 'Harpoon: pin file' },
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
    name = 'Editing',
    keys = {
      { 'v', 'J', ":m '>+1<CR>gv=gv", desc = 'Move selection down' },
      { 'v', 'K', ":m '<-2<CR>gv=gv", desc = 'Move selection up' },
      { 'n', 'Y', 'yg$', desc = 'Yank to end of line' },
      { 'n', 'J', 'mzJ`z', desc = 'Join lines (cursor stays)' },
      { 'x', '<leader>p', [["_dP]], desc = 'Paste over selection (keep register)' },
      { 'n', '<leader>y', [["+y]], desc = 'Yank to system clipboard' },
      { 'n', '<leader>Y', [["+Y]], desc = 'Yank line to system clipboard' },
      { 'n', '<leader>d', [["_d]], desc = 'Delete without yanking' },
      { 'n', '<leader>s', [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], desc = 'Substitute word under cursor' },
      { 'n', '<leader>f', function() require('czernous.format').format() end, desc = 'Format buffer (project formatter / LSP)' },
      { 'n', '<leader>x', '<cmd>!chmod +x %<CR>', desc = 'Make file executable' },
      { 'n', '<leader><leader>', function()
        if vim.bo.filetype == 'lua' or vim.bo.filetype == 'vim' then
          vim.cmd('source %')
        else
          vim.notify('Nothing to source: not a Lua/Vim file', vim.log.levels.WARN)
        end
      end, desc = 'Source current Lua/Vim file' },
      { 'n', '<leader>u', '<cmd>UndotreeToggle<cr>', desc = 'Undo tree' },
      { 'n', '<leader>tT', function() require('czernous.theme').toggle_transparency() end, desc = 'Toggle transparent background' },
    },
  },
  {
    name = 'Navigation',
    keys = {
      { 'n', '<C-d>', '<C-d>zz', desc = 'Half page down (centered)' },
      { 'n', '<C-u>', '<C-u>zz', desc = 'Half page up (centered)' },
      { 'n', 'n', 'nzzzv', desc = 'Next match (centered)' },
      { 'n', 'N', 'Nzzzv', desc = 'Previous match (centered)' },
      { 'n', 'k', "v:count == 0 ? 'gk' : 'k'", expr = true, desc = 'Up (through wrapped lines)' },
      { 'n', 'j', "v:count == 0 ? 'gj' : 'j'", expr = true, desc = 'Down (through wrapped lines)' },
      { 'n', '<C-k>', '<cmd>cnext<CR>zz', desc = 'Next quickfix item' },
      { 'n', '<C-j>', '<cmd>cprev<CR>zz', desc = 'Previous quickfix item' },
      { 'n', '<leader>k', '<cmd>lnext<CR>zz', desc = 'Next location-list item' },
      { 'n', '<leader>j', '<cmd>lprev<CR>zz', desc = 'Previous location-list item' },
    },
  },
  {
    name = 'Diagnostics',
    keys = {
      { 'n', '[d', function() vim.diagnostic.jump({ count = -1, on_jump = show_diagnostic }) end, desc = 'Previous diagnostic' },
      { 'n', ']d', function() vim.diagnostic.jump({ count = 1, on_jump = show_diagnostic }) end, desc = 'Next diagnostic' },
      { 'n', '<leader>vd', vim.diagnostic.open_float, desc = 'View diagnostic message' },
      { 'n', '<leader>q', vim.diagnostic.setloclist, desc = 'Diagnostics to location list' },
      { 'n', '<leader>ttx', '<cmd>Trouble diagnostics toggle<cr>', plugin = 'trouble.nvim', desc = 'Trouble: diagnostics (all files)' },
      { 'n', '<leader>ttd', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>', plugin = 'trouble.nvim', desc = 'Trouble: buffer diagnostics' },
      { 'n', '<leader>ttl', '<cmd>Trouble loclist toggle<cr>', plugin = 'trouble.nvim', desc = 'Trouble: location list' },
      { 'n', '<leader>ttq', '<cmd>Trouble qflist toggle<cr>', plugin = 'trouble.nvim', desc = 'Trouble: quickfix list' },
      { 'n', '<leader>ttr', '<cmd>Trouble lsp_references toggle<cr>', plugin = 'trouble.nvim', desc = 'Trouble: LSP references' },
    },
  },
  {
    name = 'Git',
    keys = {
      { 'n', '<leader>gs', '<cmd>Git<cr>', desc = 'Git status (fugitive)' },
    },
  },
  {
    -- Text objects: use after an operator or in visual mode, e.g. `daf`
    -- deletes a function, `vic` selects inside a class, `cia` changes an argument.
    name = 'Code structure (treesitter)',
    keys = {
      { { 'x', 'o' }, 'af', ts_select('@function.outer'), desc = 'a function' },
      { { 'x', 'o' }, 'if', ts_select('@function.inner'), desc = 'inner function' },
      { { 'x', 'o' }, 'ac', ts_select('@class.outer'), desc = 'a class' },
      { { 'x', 'o' }, 'ic', ts_select('@class.inner'), desc = 'inner class' },
      { { 'x', 'o' }, 'aa', ts_select('@parameter.outer'), desc = 'a parameter/argument' },
      { { 'x', 'o' }, 'ia', ts_select('@parameter.inner'), desc = 'inner parameter/argument' },
      { { 'n', 'x', 'o' }, ']m', ts_move('goto_next_start', '@function.outer'), desc = 'Next function start' },
      { { 'n', 'x', 'o' }, ']]', ts_move('goto_next_start', '@class.outer'), desc = 'Next class start' },
      { { 'n', 'x', 'o' }, ']M', ts_move('goto_next_end', '@function.outer'), desc = 'Next function end' },
      { { 'n', 'x', 'o' }, '][', ts_move('goto_next_end', '@class.outer'), desc = 'Next class end' },
      { { 'n', 'x', 'o' }, '[m', ts_move('goto_previous_start', '@function.outer'), desc = 'Previous function start' },
      { { 'n', 'x', 'o' }, '[[', ts_move('goto_previous_start', '@class.outer'), desc = 'Previous class start' },
      { { 'n', 'x', 'o' }, '[M', ts_move('goto_previous_end', '@function.outer'), desc = 'Previous function end' },
      { { 'n', 'x', 'o' }, '[]', ts_move('goto_previous_end', '@class.outer'), desc = 'Previous class end' },
      { 'n', '<leader>cn', function() require('nvim-treesitter-textobjects.swap').swap_next('@parameter.inner') end, desc = 'Swap with next parameter' },
      { 'n', '<leader>cp', function() require('nvim-treesitter-textobjects.swap').swap_previous('@parameter.inner') end, desc = 'Swap with previous parameter' },
      -- Ctrl+Space selects the node under the cursor; again grows it; Alt+Space shrinks.
      { 'n', '<C-space>', function() require('czernous.incremental_selection').init() end, desc = 'Select syntax node' },
      { 'x', '<C-space>', function() require('czernous.incremental_selection').grow() end, desc = 'Grow selection to parent node' },
      { 'x', '<M-space>', function() require('czernous.incremental_selection').shrink() end, desc = 'Shrink selection' },
    },
  },
  {
    -- Only in buffers where a language server is attached (see M.lsp).
    name = 'LSP (code intelligence)',
    buffer = 'lsp',
    keys = {
      { 'n', '<leader>rn', function() vim.lsp.buf.rename() end, desc = 'Rename symbol' },
      { 'n', '<leader>ca', function() vim.lsp.buf.code_action() end, desc = 'Code action (fixes, refactors)' },
      { 'n', 'gd', telescope('lsp_definitions'), desc = 'Go to definition' },
      { 'n', 'grr', telescope('lsp_references'), desc = 'Go to references' },
      { 'n', 'gI', telescope('lsp_implementations'), desc = 'Go to implementation' },
      { 'n', 'gD', function() vim.lsp.buf.declaration() end, desc = 'Go to declaration' },
      { 'n', '<leader>D', telescope('lsp_type_definitions'), desc = 'Type definition' },
      { 'n', 'gO', telescope('lsp_document_symbols'), desc = 'Document symbols (outline)' },
      { 'n', '<leader>ws', telescope('lsp_dynamic_workspace_symbols'), desc = 'Workspace symbols' },
      -- Press K twice to jump into the hover window (q closes it).
      { 'n', 'K', function() vim.lsp.buf.hover({ border = 'rounded', max_width = 80, max_height = 20 }) end, desc = 'Hover documentation' },
      -- Insert mode; Neovim's built-in <C-s> does the same.
      { 'i', '<C-h>', function() vim.lsp.buf.signature_help({ border = 'rounded', max_width = 80, max_height = 15 }) end, desc = 'Signature help' },
      { 'n', '<leader>wa', function() vim.lsp.buf.add_workspace_folder() end, desc = 'Workspace: add folder' },
      { 'n', '<leader>wr', function() vim.lsp.buf.remove_workspace_folder() end, desc = 'Workspace: remove folder' },
      { 'n', '<leader>wl', function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, desc = 'Workspace: list folders' },
    },
  },
  {
    -- Only in buffers inside a git repo (see M.gitsigns).
    name = 'Git hunks',
    buffer = 'gitsigns',
    keys = {
      { { 'n', 'v' }, ']c', function()
        if vim.wo.diff then return ']c' end
        vim.schedule(function() gs().nav_hunk('next') end)
        return '<Ignore>'
      end, expr = true, desc = 'Next git hunk' },
      { { 'n', 'v' }, '[c', function()
        if vim.wo.diff then return '[c' end
        vim.schedule(function() gs().nav_hunk('prev') end)
        return '<Ignore>'
      end, expr = true, desc = 'Previous git hunk' },
      { 'v', '<leader>hs', function() gs().stage_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, desc = 'Stage selected lines' },
      { 'v', '<leader>hr', function() gs().reset_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, desc = 'Reset selected lines' },
      { 'n', '<leader>hs', function() gs().stage_hunk() end, desc = 'Stage / unstage hunk' },
      { 'n', '<leader>hr', function() gs().reset_hunk() end, desc = 'Reset hunk' },
      { 'n', '<leader>hS', function() gs().stage_buffer() end, desc = 'Stage whole file' },
      { 'n', '<leader>hR', function() gs().reset_buffer() end, desc = 'Reset whole file' },
      { 'n', '<leader>hp', function() gs().preview_hunk() end, desc = 'Preview hunk' },
      { 'n', '<leader>hb', function() gs().blame_line({ full = false }) end, desc = 'Blame line' },
      { 'n', '<leader>hd', function() gs().diffthis() end, desc = 'Diff against index' },
      { 'n', '<leader>hD', function() gs().diffthis('~') end, desc = 'Diff against last commit' },
      { 'n', '<leader>tb', function() gs().toggle_current_line_blame() end, desc = 'Toggle line blame' },
      { 'n', '<leader>td', function() gs().preview_hunk_inline() end, desc = 'Show deleted lines inline' },
      { { 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>', desc = 'inner git hunk' },
    },
  },
}

-- Labels shown by which-key for key prefixes.
M.prefixes = {
  { '<leader>c', group = 'Code' },
  { '<leader>h', group = 'Git hunk' },
  { '<leader>h', group = 'Git hunk', mode = 'v' },
  { '<leader>p', group = 'Project / find' },
  { '<leader>r', group = 'Rename' },
  { '<leader>t', group = 'Toggle / Trouble' },
  { '<leader>tt', group = 'Trouble' },
  { '<leader>w', group = 'Workspace' },
  { '<leader>g', group = 'Git' },
  { '<leader>v', group = 'View' },
  { 'gr', group = 'LSP (built-in)' },
}

local function set(key, extra)
  local opts = vim.tbl_extend('force', { desc = key.desc, expr = key.expr, silent = key.expr or nil }, extra or {})
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

--- lazy.nvim `keys` spec for one plugin: `keys = require('czernous.keymaps').lazy('trouble.nvim')`.
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

--- Buffer-local LSP keys (called on LspAttach).
function M.lsp(bufnr) set_buffer_group('lsp', bufnr) end

--- Buffer-local git hunk keys (called from gitsigns on_attach).
function M.gitsigns(bufnr) set_buffer_group('gitsigns', bufnr) end

--- which-key `spec`: the group labels above. (A check fails if a label's
--- prefix has no keys, so this list can't go stale.)
function M.which_key() return M.prefixes end

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
