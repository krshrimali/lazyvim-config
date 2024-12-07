-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>me", require("lsp_lines").toggle)
vim.keymap.set("n", "<leader>mf", function()
  vim.diagnostic.config({ virtual_text = not vim.diagnostic.config().virtual_text })
end)
