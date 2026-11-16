-- Syntax support must include usable queries, not merely an active highlighter.
vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
  vim.defer_fn(function()
    local ok, err = xpcall(function()
      local fixture = (vim.env.CHECK_ASTRO_FIXTURE or vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/fixtures/astro/index.astro')
      vim.cmd.edit(fixture)
      local buf = vim.api.nvim_get_current_buf()
      assert(vim.bo[buf].filetype == 'astro', 'Astro filetype was not detected')
      assert(vim.wait(tonumber(vim.env.CHECK_ASTRO_TIMEOUT) or 45000, function()
        return #vim.treesitter.query.get_files('astro', 'highlights') > 0
          and vim.treesitter.highlighter.active[buf] ~= nil
      end,50), 'Astro parser exists but highlighting queries/readiness are missing')
      local parser = assert(vim.treesitter.get_parser(buf, 'astro'))
      local query = assert(vim.treesitter.query.get('astro','highlights'))
      local count = 0
      for _ in query:iter_captures(parser:parse()[1]:root(),buf) do count = count + 1 end
      assert(count > 0, 'Astro queries produced no captures')
      print('PASS Astro detection and nonempty highlight captures')
    end,debug.traceback)
    if not ok then io.stderr:write(err..'\n');vim.cmd('cquit 1') end
    vim.cmd('qa!')
  end,100)
end })
