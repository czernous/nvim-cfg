
vim.keymap.set("n", "<leader>ttx", "<cmd>TroubleToggle<cr>",
  {silent = true, noremap = true},
  {desc = "[t]rouble[t]oggle e[x]ecute (start)"}
)
vim.keymap.set("n", "<leader>ttw", "<cmd>TroubleToggle workspace_diagnostics<cr>",
  {silent = true, noremap = true},
  {dec = "[t]rouble[t]oggle [w]orkspace diagnostics"}
)
vim.keymap.set("n", "<leader>ttd", "<cmd>TroubleToggle document_diagnostics<cr>",
  {silent = true, noremap = true},
  {dec = "[t]rouble[t]oggle [d]ocument diagnostics"}
)
vim.keymap.set("n", "<leader>ttl", "<cmd>TroubleToggle loclist<cr>",
  {silent = true, noremap = true},
  {desc = "[t]rouble[t]oggle [l]oclist"}
)
vim.keymap.set("n", "<leader>ttq", "<cmd>TroubleToggle quickfix<cr>",
  {silent = true, noremap = true},
  {desc = "[t]rouble[toggle] [q]uickfix"}
)
vim.keymap.set("n", "gR", "<cmd>TroubleToggle lsp_references<cr>",
  {silent = true, noremap = true},
  {desc = "TroubleToggle lsp_references"}
)
