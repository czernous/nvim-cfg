-- Language servers.
--
-- A server starts only if its program is on $PATH: from the language's own
-- toolchain (rustup, go install, dotnet tool) or a Nix devshell. Mason is a
-- manual fallback (:MasonInstall <name>, picked up without a restart); its bin
-- dir is at the END of $PATH,
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
  kotlin_language_server = 'kotlin-language-server', -- .kt and Gradle .kts files
}

--- Names of servers found and enabled (filled shortly after startup).
M.enabled = {}
--- True once the background lookup has finished.
M.ready = false

function M.setup()
  -- How errors and warnings are shown. Set here, not in options.lua: loading
  -- Neovim's diagnostics module costs ~1 ms, and this runs after the first screen.
  -- No inline (virtual) text and no gutter signs -- by choice, for speed and calm.
  -- Find errors with: the counts in the statusline, underlines, ]d / [d (jump +
  -- popup) and the diagnostics list.
  vim.diagnostic.config({
    signs = false,
    virtual_text = false,
    severity_sort = true,
    float = { border = 'rounded', source = true },
  })

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
    -- Tell every server what the completion engine supports (snippets, lazy
    -- documentation, ...). This runs after the first screen, so asking blink
    -- here costs nothing at launch.
    capabilities = require('blink.cmp').get_lsp_capabilities(),
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

  -- Bring in the server defaults (nvim-lspconfig) and Mason's bin folder now:
  -- both must be in place before servers are looked up and enabled.
  vim.api.nvim_exec_autocmds('User', { pattern = 'CzernousLspSetup', modeline = false })
  M.refresh()

  -- A server installed with :MasonInstall should start without restarting
  -- Neovim. Mason's registry is only loaded once its window opens (so it costs
  -- nothing at startup); from then on every finished install re-runs the lookup.
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('czernous_lsp_mason', { clear = true }),
    pattern = 'mason',
    once = true,
    callback = function()
      require('mason-registry'):on('package:install:success', vim.schedule_wrap(M.refresh))
    end,
  })
end

--- Look for the programs of servers that aren't enabled yet and enable the ones
--- found. Runs in a background shell: on machines whose $PATH has slow entries
--- (network or Windows mounts) every miss costs ~100ms, so this never blocks.
local refreshing, again = false, false
function M.refresh()
  -- One lookup at a time; a request arriving meanwhile triggers one more afterwards
  -- (several packages finishing a Mason install would otherwise race).
  if refreshing then again = true; return end
  refreshing = true
  local names, exes = {}, {}
  for name, exe in pairs(M.servers) do
    if not vim.tbl_contains(M.enabled, name) then names[#names + 1] = name; exes[#exes + 1] = exe end
  end
  if #names == 0 then M.ready = true; refreshing = false; return end
  local script = 'for e in "$@"; do command -v "$e" >/dev/null 2>&1 && echo "$e"; done'
  vim.system(vim.list_extend({ 'sh', '-c', script, 'sh' }, exes), { text = true }, function(r)
    vim.schedule(function()
      local found, new = {}, {}
      for line in (r.stdout or ''):gmatch('[^\n]+') do found[line] = true end
      for i, name in ipairs(names) do
        if found[exes[i]] then new[#new + 1] = name end
      end
      local function enable()
        if #new > 0 then
          vim.lsp.enable(new)
          vim.list_extend(M.enabled, new)
          table.sort(M.enabled)
        end
        M.ready = true
        refreshing = false
        if again then again = false; M.refresh() end
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

--- K: documentation for the thing under the cursor. With no language server
--- attached it says so (naming the language) instead of failing silently.
function M.hover()
  local buf = vim.api.nvim_get_current_buf()
  if #vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/hover' }) > 0 then
    -- press K again to jump into the popup; q closes it
    vim.lsp.buf.hover({ border = 'rounded', max_width = 80, max_height = 20 })
    return
  end
  local filetype = vim.bo[buf].filetype
  if filetype == 'help' or filetype == 'vim' or filetype == 'man' or filetype == '' then
    vim.cmd('normal! K') -- Vim's own lookup (help pages, man pages)
    return
  end
  vim.notify(('No language server is running for %s files, so there is no documentation to show.\n'
    .. 'Install one (it is picked up from $PATH) -- :checkhealth czernous lists what is missing.'):format(filetype), vim.log.levels.INFO)
end

return M
