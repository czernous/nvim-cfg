return {
    {
        'folke/which-key.nvim',
        event = 'VeryLazy',
        config = function()
            require('which-key').add {
                { '<leader>c', group = '[C]ode' },
                { '<leader>d', group = '[D]ocument' },
                { '<leader>g', group = '[G]it' },
                { '<leader>h', group = 'Git [H]unk' },
                { '<leader>r', group = '[R]ename' },
                { '<leader>s', group = '[S]earch' },
                { '<leader>t', group = '[T]oggle' },
                { '<leader>w', group = '[W]orkspace' },

                -- Visual mode mappings
                { '<leader>',  group = 'VISUAL <leader>', mode = 'v' },
                { '<leader>h', group = 'Git [H]unk',      mode = 'v' },
            }
        end,
    }
}
