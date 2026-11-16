-- Provision once before checks; surface install failures as a nonzero exit.
local ok, err = xpcall(function()
  local ts = require('nvim-treesitter')
  local want = require('czernous.treesitter').parsers
  ts.install(want):wait(600000)
  local installed = ts.get_installed()
  local missing = vim.tbl_filter(function(lang) return not vim.tbl_contains(installed, lang) end, want)
  assert(#missing == 0, 'Parser provisioning incomplete: ' .. table.concat(missing, ', '))
  print(('Parser bundles ready: %d'):format(#want))
end, debug.traceback)
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') end
vim.cmd('qa!')
