return {
    {
        'nvim-telescope/telescope.nvim',
        -- master (not the frozen 0.1.x) -- its previewer uses core treesitter
        -- (vim.treesitter.*), required for compatibility with nvim-treesitter main.
        branch = 'master',
        dependencies = {
          'nvim-lua/plenary.nvim',
          -- Fuzzy Finder Algorithm which requires local dependencies to be built.
          -- Only load if `make` is available. Make sure you have the system
          -- requirements installed.
          {
            'nvim-telescope/telescope-fzf-native.nvim',
            -- NOTE: If you are having trouble with this installation,
            --       refer to the README for telescope-fzf-native for more instructions.
            build = 'make',
            cond = function()
              return vim.fn.executable 'make' == 1
            end,
          },
        },
      },
}