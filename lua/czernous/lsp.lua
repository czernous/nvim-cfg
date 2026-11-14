-- Language servers.
--
-- A server starts only if its program is on $PATH: from the language's own
-- toolchain (rustup, go install, dotnet tool) or a Nix devshell. Mason is a
-- manual fallback (:MasonInstall <name>); its bin dir is at the END of $PATH,
-- so a toolchain/devshell copy always wins. Language/SDK versions are chosen by
-- the environment you start Neovim in, never here.
--
-- Adding a language: one line in M.servers  (lspconfig name = program name).
-- Special settings for a server go in after/lsp/<name>.lua.
-- Keys for LSP buffers are in keymaps.lua (group 'LSP').

local M = {}

M.servers = {
  gopls = 'gopls',
  rust_analyzer = 'rust-analyzer',
  lua_ls = 'lua-language-server',
  jdtls = 'jdtls',
  csharp_ls = 'csharp-ls',
  vtsls = 'vtsls',
}

--- Names of servers found and enabled (filled shortly after startup).
M.enabled = {}
--- True once the background lookup has finished.
M.ready = false

function M.setup()
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('czernous_lsp', { clear = true }),
    desc = 'LSP keymaps and :Format',
    callback = function(event)
      require('czernous.keymaps').lsp(event.buf)
      vim.api.nvim_buf_create_user_command(event.buf, 'Format', function()
        require('czernous.format').format() -- same as <leader>f
      end, { desc = 'Format current buffer (same as <leader>f)' })
    end,
  })

  vim.lsp.config('*', {
    -- nvim-cmp completion capabilities for every server.
    capabilities = require('cmp_nvim_lsp').default_capabilities(),
    -- A server that crashes before it finishes starting (e.g. a rustup proxy
    -- without the component installed) is disabled for this session, instead
    -- of being restarted -- and warning -- for every file you open.
    on_exit = function(code, _, client_id)
      local client = vim.lsp.get_client_by_id(client_id)
      if code ~= 0 and client and not client.initialized then
        vim.schedule(function() vim.lsp.enable(client.name, false) end)
      end
    end,
  })

  -- Find which server programs exist WITHOUT blocking startup: on machines
  -- whose $PATH has slow entries (network or Windows mounts) every miss costs
  -- ~100ms. A background shell does the lookups; found servers are then
  -- enabled, and attach to any buffers already open.
  local names, exes = {}, {}
  for name, exe in pairs(M.servers) do names[#names + 1] = name; exes[#exes + 1] = exe end
  local script = 'for e in "$@"; do command -v "$e" >/dev/null 2>&1 && echo "$e"; done'
  vim.system(vim.list_extend({ 'sh', '-c', script, 'sh' }, exes), { text = true }, function(r)
    vim.schedule(function()
      local found = {}
      for line in (r.stdout or ''):gmatch('[^\n]+') do found[line] = true end
      M.enabled = {}
      for i, name in ipairs(names) do
        if found[exes[i]] then table.insert(M.enabled, name) end
      end
      table.sort(M.enabled)
      local function enable()
        if #M.enabled > 0 then vim.lsp.enable(M.enabled) end
        M.ready = true
      end
      -- Neovim only attaches already-open buffers once startup has finished,
      -- so if we got here early (something waited during startup), wait for it.
      if vim.v.vim_did_enter == 1 then
        enable()
      else
        vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = enable })
      end
    end)
  end)
end

return M
