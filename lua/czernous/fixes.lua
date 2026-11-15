-- "A fix is available": tells the statusline when the language server offers a
-- quick fix on the line the cursor is on, and opens the list of fixes.
--
-- Cheap by construction: nothing happens while you move. Only when the cursor
-- has rested (CursorHold) AND the line has a problem is the server asked, in the
-- background. The answer is stored on the buffer (vim.b.czernous_fix = line
-- number) and the statusline shows `fix` while the cursor is still on that line.

local M = {}

local function set(buf, value)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].czernous_fix == value then return end
  vim.b[buf].czernous_fix = value
  require('czernous.statusline').update()
end

local function look(buf)
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local problems = vim.diagnostic.get(buf, { lnum = lnum })
  if #problems == 0 then return set(buf, nil) end
  local clients = vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/codeAction' })
  if #clients == 0 then return set(buf, nil) end
  local client = clients[1]
  local line = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1] or ''
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    range = { start = { line = lnum, character = 0 }, ['end'] = { line = lnum, character = #line } },
    context = {
      diagnostics = vim.tbl_map(function(d) return d.user_data and d.user_data.lsp or nil end, problems),
      only = { 'quickfix' },
      triggerKind = 2, -- automatic: servers may skip expensive computations
    },
  }
  client:request('textDocument/codeAction', params, function(err, result)
    if err or not vim.api.nvim_buf_is_valid(buf) then return end
    -- still on that line? (the cursor may have moved while the server answered)
    local now = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_win_get_cursor(0)[1] - 1 or -1
    set(buf, (result and #result > 0 and now == lnum) and lnum or nil)
  end, buf)
end

function M.setup()
  vim.api.nvim_create_autocmd('CursorHold', {
    group = vim.api.nvim_create_augroup('czernous_fixes', { clear = true }),
    desc = 'Ask whether a fix is available on this line',
    callback = function(ev)
      if vim.bo[ev.buf].buftype == '' then look(ev.buf) end
    end,
  })
end

--- Show the fixes offered at the cursor, each with a preview of what it changes.
function M.show() require('actions-preview').code_actions() end

return M
