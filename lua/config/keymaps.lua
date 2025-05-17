-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = true, silent = true })

-- Define a function to echo the relative path and copy it to the clipboard
function ShowAndCopyRelativePath()
  local relpath = vim.fn.expand("%")
  print(relpath)
  vim.fn.setreg("+", relpath)
end

function ShowAndCopyAbsolutePath()
  local abspath = vim.fn.expand("%:p")
  print(abspath)
  vim.fn.setreg("+", abspath)
end

-- Map <leader>r to call the function
vim.api.nvim_set_keymap("n", "<leader>gr", ":lua ShowAndCopyRelativePath()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>ga", ":lua ShowAndCopyAbsolutePath()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("i", "<C-l>", 'copilot#Accept("<CR>")', { expr = true, silent = true })
vim.keymap.set("v", "<leader>cf", vim.lsp.buf.format, {})
vim.keymap.set('n', '<leader>sf', function()
  require('telescope.builtin').lsp_dynamic_workspace_symbols({
    symbols = { 'function', 'method' }
  })
end, { desc = 'Search functions in workspace' })
