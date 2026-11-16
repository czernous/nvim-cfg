-- Run: nvim --headless -n -i NONE '+luafile tests/parser-query-check.lua'
-- Optional CHECK_PARSER selects an explicit parser for provenance diagnostics.
local ok, err = xpcall(function()
  local path = vim.env.CHECK_PARSER
  if path and path ~= '' then vim.treesitter.language.add('lua', { path = path }) end
  local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
  local fixture = root .. '/fixtures/lua/init.lua'
  if vim.fn.filereadable(fixture) == 1 then vim.cmd.edit(fixture) end
  require('lazy').load({ plugins = { 'nvim-treesitter' } })
  -- Test a later Lua buffer too: the startup buffer can preload a system parser.
  vim.cmd.enew()
  vim.bo.filetype = 'lua'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local function add(a, b)', '  return a + b', 'end' })
  vim.treesitter.get_parser(0, 'lua'):parse()
  for _, kind in ipairs({ 'highlights', 'injections' }) do
    assert(vim.treesitter.query.get('lua', kind), 'missing Lua ' .. kind .. ' query')
  end
  vim.treesitter.start(0, 'lua')
  assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'Lua highlighting inactive')
end, debug.traceback)
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') end
print('PASS Lua parser/query compatibility and highlighting')
vim.cmd('qa!')
