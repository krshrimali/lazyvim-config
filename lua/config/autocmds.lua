-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
vim.api.nvim_create_autocmd({ "FileType" }, {
  pattern = { "*" },
  callback = function()
    vim.b.autoformat = false
  end,
})

if vim.g.loaded_git_code_evolution then
  return
end
vim.g.loaded_git_code_evolution = true

-- Create user commands
vim.api.nvim_create_user_command('GitCodeEvolution', function(opts)
  require('plugins.testing').show_code_evolution()
end, {range = true})

vim.api.nvim_create_user_command('GitFileHistory', function()
  require('plugins.testing').show_file_history()
end, {})
