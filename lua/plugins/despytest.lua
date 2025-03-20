-- Define the plugin
local M = {}

-- Helper function to get the relative file path of the current file
local function get_relative_file_path()
  return vim.fn.expand('%')
end

-- Helper function to get the name of the test function under the cursor
local function get_test_function_name()
  local current_line = vim.fn.getline('.')
  local match = string.match(current_line, '%s*def%s*(test[_%w]*)')
  if match then
    return match
  else
    print("Error: No test function found on the current line")
    return nil
  end
end

-- Command to execute the despytest command in a new terminal buffer
function M.run_despytest()
  local relative_file_path = get_relative_file_path()
  local test_function_name = get_test_function_name()

  if test_function_name then
    local cmd = "despytest " .. relative_file_path .. " -k " .. test_function_name

    -- Open a new terminal buffer and run the command
    vim.cmd("vnew | term " .. cmd)
  end
end

-- Define a user command for easy access
vim.api.nvim_create_user_command('RunDespytest', M.run_despytest, {})

return M
