-- Fuzzy finder. Keys are in keymaps.lua (group 'Files & search').
return {
  {
    'nvim-telescope/telescope.nvim',
    -- master (not the frozen 0.1.x): its previewer uses core treesitter,
    -- required for compatibility with nvim-treesitter main.
    branch = 'master',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        -- Native fuzzy sorter; needs `make` and a C compiler.
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function() return vim.fn.executable('make') == 1 end,
      },
    },
    config = function()
      local telescope = require('telescope')
      telescope.setup({
        defaults = {
          mappings = {
            i = { ['<C-u>'] = false, ['<C-d>'] = false },
          },
        },
      })
      pcall(telescope.load_extension, 'fzf')

      -- :LiveGrepGitRoot -- live grep from the git root of the current file.
      vim.api.nvim_create_user_command('LiveGrepGitRoot', function()
        local file = vim.api.nvim_buf_get_name(0)
        local dir = file == '' and vim.fn.getcwd() or vim.fn.fnamemodify(file, ':h')
        local root = vim.fn.systemlist({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' })[1]
        if vim.v.shell_error ~= 0 then
          vim.notify('Not a git repository. Searching current directory.')
          root = vim.fn.getcwd()
        end
        require('telescope.builtin').live_grep({ search_dirs = { root } })
      end, { desc = 'Live grep from git root' })
    end,
  },
}
