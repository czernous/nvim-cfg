-- Astro needs a TypeScript SDK as well as astro-ls. Use the project's SDK first;
-- Mason's installed server supplies an explicit fallback for loose files.
local function sdk(root, explicit)
  if explicit and explicit ~= '' then
    if vim.uv.fs_stat(explicit .. '/typescript.js') then return explicit end
    return nil
  end
  local git = vim.fs.root(root, '.git')
  local file = vim.fs.find('node_modules/typescript/lib/typescript.js', {
    path = root, upward = true, stop = git and vim.fs.dirname(git) or nil,
  })[1]
  if file then return vim.fs.dirname(file) end
  local fallback = vim.fn.stdpath('data') .. '/mason/packages/astro-language-server/node_modules/typescript/lib'
  if vim.uv.fs_stat(fallback .. '/typescript.js') then return fallback end
end

return {
  root_dir = function(buf, on_dir)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local path = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
    local git = vim.fs.root(path, '.git')
    local marker = vim.fs.find({ 'package.json', 'tsconfig.json', 'jsconfig.json' }, {
      path = path, upward = true, stop = git and vim.fs.dirname(git) or nil,
    })[1]
    local root = marker and vim.fs.dirname(marker) or git or path
    local options = vim.lsp.config.astro.init_options or {}
    if not sdk(root, options.typescript and options.typescript.tsdk) then
      vim.b[buf].czernous_astro_missing_tool = 'Astro needs a TypeScript SDK. Install project dependencies using its lockfile, provide an SDK in the project environment, or use :MasonInstall astro-language-server for the default bundle.'
      vim.notify(vim.b[buf].czernous_astro_missing_tool, vim.log.levels.WARN)
      return
    end
    vim.b[buf].czernous_astro_missing_tool = nil
    on_dir(root)
  end,
  before_init = function(_, config)
    config.init_options = config.init_options or {}
    config.init_options.typescript = config.init_options.typescript or {}
    config.init_options.typescript.tsdk = sdk(config.root_dir, config.init_options.typescript.tsdk)
  end,
}
