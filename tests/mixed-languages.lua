-- Run: nvim --headless -n -i NONE '+luafile tests/mixed-languages.lua'
-- Requires working C#, TypeScript and Go servers; absence is a failure here.
local function check()
  local root = vim.fn.tempname()
  local fixture_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/fixtures'
  for _, dir in ipairs({ 'services/api', 'services/go', 'web' }) do vim.fn.mkdir(root .. '/' .. dir, 'p') end
  assert(vim.system({ 'git', 'init', '-q', root }):wait(10000).code == 0, 'fixture git init')
  vim.fn.writefile({ '<Solution><Project Path="services/api/fixture.csproj" /></Solution>' }, root .. '/mixed.slnx')
  vim.fn.writefile(vim.fn.readfile(fixture_dir .. '/csharp/fixture.csproj'), root .. '/services/api/fixture.csproj')
  vim.fn.writefile(vim.fn.readfile(fixture_dir .. '/csharp/Program.cs'), root .. '/services/api/Program.cs')
  vim.fn.writefile({ 'module mixedgo', 'go 1.21' }, root .. '/services/go/go.mod')
  vim.fn.writefile({ 'package main', 'import "fmt"', 'func add(a,b int) int { return a+b }', 'func main() { fmt.Println(add(1,2)) }' }, root .. '/services/go/main.go')
  vim.fn.writefile({ '{"name":"mixed-web","private":true}' }, root .. '/web/package.json')
  vim.fn.writefile({ '{"compilerOptions":{"strict":true,"target":"ES2022"},"include":["index.ts"]}' }, root .. '/web/tsconfig.json')
  vim.fn.writefile(vim.fn.readfile(fixture_dir .. '/ts/index.ts'), root .. '/web/index.ts')
  local cases = {
    {file='services/api/Program.cs', lang='c_sharp', server='csharp_ls', symbol='Add', root=root},
    {file='web/index.ts', lang='typescript', server='vtsls', symbol='add', root=root},
    {file='services/go/main.go', lang='go', server='gopls', symbol='add', root=root..'/services/go'},
  }
    vim.api.nvim_exec_autocmds('User', {pattern='VeryLazy'})
    for _, spec in ipairs(cases) do
      local start=vim.uv.hrtime()
      vim.cmd.edit(root..'/'..spec.file)
      local buf=vim.api.nvim_get_current_buf()
      assert(vim.treesitter.get_parser(buf,spec.lang):parse()[1],spec.file..' parse')
      vim.treesitter.start(buf,spec.lang)
      assert(vim.treesitter.highlighter.active[buf],spec.file..' highlight')
      local client
      assert(vim.wait(60000,function()
        client=vim.lsp.get_clients({bufnr=buf,name=spec.server})[1]
        return client and client.initialized
      end,50),spec.file..' LSP attach timeout')
      assert(vim.fs.normalize(client.root_dir)==vim.fs.normalize(spec.root),spec.file..' root='..tostring(client.root_dir))
      local lines=vim.api.nvim_buf_get_lines(buf,0,-1,false)
      local line=lines[#lines]; local col=assert(line:find(spec.symbol,1,true))
      vim.api.nvim_win_set_cursor(0,{#lines,col-1})
      local params=vim.lsp.util.make_position_params(0,client.offset_encoding)
      local result=client:request_sync('textDocument/definition',params,15000,buf)
      assert(result and result.result and (result.result.uri or result.result.targetUri or #result.result>0),spec.file..' definition')
      local completion=client:request_sync('textDocument/completion',params,15000,buf)
      local items=completion and completion.result and (completion.result.items or completion.result)
      assert(items and #items>0,spec.file..' completion')
      assert(vim.iter(items):any(function(item) return item.label:find(spec.symbol,1,true) ~= nil end),spec.file..' completion lacks local function')
      io.stdout:write(('PASS mixed %s: highlight, LSP, definition, completion, root; %.1f ms to verified results\n'):format(spec.file,(vim.uv.hrtime()-start)/1e6))
    end
    -- Return to the first language in the same session without restarting clients.
    vim.cmd.edit(root..'/'..cases[1].file)
    assert(#vim.lsp.get_clients({bufnr=0,name='csharp_ls'})==1,'C# client reused once')

end

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.defer_fn(function()
      local ok, err = xpcall(check, debug.traceback)
      if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') end
      vim.cmd('qa!')
    end, 100)
  end,
})
