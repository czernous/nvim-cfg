vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
  require('czernous.lsp').servers.pyright = 'nvim-test-missing-pyright'
  vim.defer_fn(function()
    local ok, err = xpcall(function()
      vim.cmd.edit((vim.env.CHECK_PYTHON_FIXTURE or vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/fixtures/python/main.py'))
      assert(vim.wait(10000, function()
        local c = vim.lsp.get_clients({bufnr=0,name='ruff'})[1]
        return require('czernous.lsp').ready and c and c.initialized
      end,50), 'Ruff-only fixture not ready')
      vim.api.nvim_win_set_cursor(0,{5,9})
      local messages={}
      vim.notify=function(message) messages[#messages+1]=tostring(message) end
      vim.api.nvim_feedkeys(vim.keycode('K'),'x',false)
      vim.wait(500)
      local hover=table.concat(messages,'\n')
      assert(hover:find(':MasonInstall pyright',1,true), 'K missing installation advice: '..hover)
      assert(hover:find('nvim-test-missing-pyright',1,true), 'K missing executable name')
      local warnings={}
      for _,name in ipairs({'start','ok','info','error'}) do vim.health[name]=function() end end
      vim.health.warn=function(message,advice) warnings[#warnings+1]=tostring(message)..'\n'..table.concat(advice or {},'\n') end
      require('czernous.health').check()
      assert(table.concat(warnings,'\n'):find(':MasonInstall pyright',1,true), 'health missing installation advice')
      print('PASS Python missing-tool advice from K and checkhealth')
    end,debug.traceback)
    if not ok then io.stderr:write(err..'\n');vim.cmd('cquit 1') end
    vim.cmd('qa!')
  end,100)
end })
