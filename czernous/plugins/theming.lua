
return {
    {
        'navarasu/onedark.nvim',
        name = 'onedark',
        priority = 1000,
        config = function()
            require('onedark').setup {
                style = 'warm'
            }
        end
    },
    { 
        "catppuccin/nvim", 
        name = "catppuccin", 
        priority = 1000 
    },
    {
        'nvim-tree/nvim-web-devicons'
    }
}