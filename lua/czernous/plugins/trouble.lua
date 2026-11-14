-- trouble.nvim v3: the old `:TroubleToggle <mode>` commands were replaced by
-- `:Trouble <mode> toggle`. Keymaps live in `keys` so they also lazy-load it.
return {
  {
    "folke/trouble.nvim",
    dependencies = "nvim-tree/nvim-web-devicons",
    cmd = "Trouble",
    opts = {},
    keys = {
      { "<leader>ttx", "<cmd>Trouble diagnostics toggle<cr>", desc = "[t]rouble [t]oggle diagnostics" },
      { "<leader>ttw", "<cmd>Trouble diagnostics toggle<cr>", desc = "[t]rouble [t]oggle [w]orkspace diagnostics" },
      { "<leader>ttd", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "[t]rouble [t]oggle [d]ocument diagnostics" },
      { "<leader>ttl", "<cmd>Trouble loclist toggle<cr>", desc = "[t]rouble [t]oggle [l]oclist" },
      { "<leader>ttq", "<cmd>Trouble qflist toggle<cr>", desc = "[t]rouble [t]oggle [q]uickfix" },
      { "tgR", "<cmd>Trouble lsp_references toggle<cr>", desc = "Trouble LSP references" },
    },
  },
}
