-- Finding your way around.
--
-- <leader>pk -- the key cheat sheet: every key this config defines (from the
--   registry in keymaps.lua) plus the built-in Neovim keys worth knowing, as
--   one searchable list: group, key, what it does. Type to filter; Enter on a
--   normal-mode key presses it for you.
--
-- :help (and <leader>ph) -- the help page takes over the window you were in
--   instead of splitting the screen; `q` goes back to what you were editing.

local M = {}

-- Built-in keys that are easy not to know about. (Keys defined by this config
-- are read from keymaps.lua and are not repeated here.)
M.builtins = {
  { 'n', 'gd', 'Go to the definition (inside this file); <C-]> asks the language server' },
  { 'n', '<C-]>', 'Go to the definition of the thing under the cursor' },
  { 'n', '<C-o>', 'Go back to where you were (and <C-i> forward again)' },
  { 'n', 'grn', 'Rename the thing under the cursor everywhere' },
  { 'n', 'grr', 'Where is this used? (references)' },
  { 'n', 'gri', 'Go to the implementation' },
  { 'n', 'grt', 'Go to the type definition' },
  { 'n', 'gO', "This file's outline (functions, classes)" },
  { 'i', '<C-s>', 'Show the arguments of the call you are typing' },
  { 'n', ']d', 'Next problem (and [d previous)' },
  { 'n', '<C-w>d', 'Show the problem under the cursor' },
  { 'n', ']q', 'Next entry of the quickfix list (and [q previous)' },
  { 'n', 'gcc', 'Comment / uncomment the line (gc + a motion, or gc on a selection)' },
  { 'n', 'u', 'Undo (and <C-r> redo)' },
  { 'n', '.', 'Repeat the last change' },
  { 'n', '*', 'Search for the word under the cursor (n next, N previous)' },
  { 'n', '%', 'Jump to the matching bracket' },
  { 'n', 'ciw', 'Change the word under the cursor (ci" inside quotes, ci( inside brackets)' },
  { 'n', '<C-w>v', 'Split the window side by side (<C-w>s stacked, <C-w>q close, <C-w>w next)' },
  { 'n', 'gx', 'Open the link under the cursor' },
  { 'n', 'q:', 'History of : commands' },
  { 'n', 'ZZ', 'Save and close' },
}

local mode_names = { n = '', x = 'visual', v = 'visual', i = 'insert', o = 'after an operator', t = 'terminal', c = 'command line' }

--- Keys as people read them: `Space pf` rather than `<leader>pf`.
local function readable(lhs) return (lhs:gsub('<[lL]eader>', 'Space '):gsub('<localleader>', '\\ ')) end

--- Every cheat-sheet line: { group, lhs, key (readable), desc, mode }.
--- One line per key: a key defined for several modes is listed once.
function M.entries()
  local out, seen = {}, {}
  local function add(group, mode, lhs, desc)
    local id = lhs .. '\0' .. desc
    if seen[id] then
      if mode == 'n' then seen[id].mode = 'n' end
      return
    end
    local entry = { group = group, lhs = lhs, key = readable(lhs), desc = desc, mode = mode }
    seen[id] = entry
    out[#out + 1] = entry
  end
  for _, key in ipairs(require('czernous.keymaps').all()) do add(key.group, key.mode, key.lhs, key.desc) end
  for _, key in ipairs(M.builtins) do add('Built into Neovim', key[1], key[2], key[3]) end
  return out
end

--- Open the cheat sheet.
function M.cheatsheet()
  local pickers, finders, config = require('telescope.pickers'), require('telescope.finders'), require('telescope.config').values
  local actions, state = require('telescope.actions'), require('telescope.actions.state')
  local entries = M.entries()
  local group_width, key_width = 0, 0
  for _, e in ipairs(entries) do
    group_width, key_width = math.max(group_width, #e.group), math.max(key_width, #e.key)
  end
  local displayer = require('telescope.pickers.entry_display').create({
    separator = '   ',
    items = { { width = group_width }, { width = key_width }, { remaining = true } },
  })
  pickers.new(require('telescope.themes').get_ivy({ layout_config = { height = 0.6 } }), {
    prompt_title = 'Keys',
    results_title = 'type to filter   Enter presses the key',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(e)
        local note = mode_names[e.mode] ~= '' and ('  (' .. (mode_names[e.mode] or e.mode) .. ')') or ''
        return {
          value = e,
          ordinal = e.group .. ' ' .. e.key .. ' ' .. e.lhs .. ' ' .. e.desc,
          display = function() return displayer({ { e.group, 'Comment' }, { e.key, 'Special' }, e.desc .. note }) end,
        }
      end,
    }),
    sorter = config.generic_sorter({}),
    attach_mappings = function(prompt_buf)
      actions.select_default:replace(function()
        local chosen = state.get_selected_entry()
        actions.close(prompt_buf)
        -- only plain normal-mode keys can simply be pressed for you
        if chosen and chosen.value.mode == 'n' then
          vim.schedule(function() vim.api.nvim_feedkeys(vim.keycode(chosen.value.lhs), 'm', false) end)
        end
      end)
      return true
    end,
  }):find()
end

--- A help page has just opened in a split of its own: show it in the window
--- the user was in instead, and let `q` go back.
function M.full_window(help_buf)
  local help_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(help_win) ~= help_buf or vim.api.nvim_win_get_config(help_win).relative ~= '' then return end
  local wins = vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == '' end, vim.api.nvim_tabpage_list_wins(0))
  -- the window the user came from; if Neovim doesn't know one, any other window will do
  local function usable(w)
    return w ~= 0 and w ~= help_win and vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_config(w).relative == ''
      and vim.bo[vim.api.nvim_win_get_buf(w)].buftype ~= 'help'
  end
  local from_win = vim.fn.win_getid(vim.fn.winnr('#'))
  if not usable(from_win) then from_win = vim.tbl_filter(usable, wins)[1] end
  if from_win then
    local view = vim.fn.winsaveview()
    vim.b[help_buf].czernous_help_from = vim.api.nvim_win_get_buf(from_win)
    vim.api.nvim_win_set_buf(from_win, help_buf)
    vim.api.nvim_win_close(help_win, true)
    vim.api.nvim_set_current_win(from_win)
    vim.fn.winrestview(view)
  end
  vim.keymap.set('n', 'q', function()
    local from = vim.b[help_buf].czernous_help_from
    if from and vim.api.nvim_buf_is_valid(from) then
      vim.api.nvim_win_set_buf(0, from)
    else
      vim.cmd('helpclose')
    end
  end, { buffer = help_buf, nowait = true, desc = 'Leave the help page' })
end

return M
