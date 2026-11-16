-- Runtime download opt-out must suppress both eager and first-file installs.
vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
  vim.defer_fn(function()
    local ok, err = xpcall(function()
      local ts = require('nvim-treesitter')
      local installs = 0
      ts.get_installed = function() return {} end
      ts.install = function()
        installs = installs + 1
        return { await = function() end }
      end
      require('czernous.treesitter').setup()
      vim.cmd.edit('tests/fixtures/lua/init.lua')
      assert(installs == 0, 'automatic parser downloads ran despite NVIM_TS_AUTO_INSTALL=0: ' .. installs)
      assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'existing local syntax stopped working when downloads were disabled')
      print('PASS parser download opt-out preserves local highlighting')
    end, debug.traceback)
    if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') end
    vim.cmd('qa!')
  end, 100)
end })
