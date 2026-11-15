-- Merged on top of nvim-lspconfig's clangd defaults.
--
-- clangd needs the project's compile database (compile_commands.json: include
-- paths, language standard, defines) and only looks for it beside the sources
-- and in `build/`. CMake presets put it one level deeper (build/<preset>/), so
-- a project either says where in a `.clangd` file -- then that is used and
-- nothing happens here -- or the newest build/*/compile_commands.json is
-- handed to clangd when it starts.
return {
  before_init = function(params, config)
    local root = config.root_dir
    if type(root) ~= 'string' then return end
    for _, known in ipairs({ '.clangd', 'compile_commands.json', 'build/compile_commands.json' }) do
      if vim.uv.fs_stat(root .. '/' .. known) then return end
    end
    local newest, newest_time
    for _, file in ipairs(vim.fn.glob(root .. '/build/*/compile_commands.json', false, true)) do
      local stat = vim.uv.fs_stat(file)
      if stat and (not newest_time or stat.mtime.sec > newest_time) then newest, newest_time = file, stat.mtime.sec end
    end
    if newest then
      params.initializationOptions = params.initializationOptions or {}
      params.initializationOptions.compilationDatabasePath = vim.fs.dirname(newest)
    end
  end,
}
