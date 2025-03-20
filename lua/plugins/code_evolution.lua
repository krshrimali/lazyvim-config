-- lua/plugins/git_code_evolution.lua
local api = vim.api
local fn = vim.fn

local M = {}
local config = {
  commit_count = 5, -- Default number of commits to show
  include_context = true, -- Show surrounding lines for context
  context_lines = 5, -- Number of context lines before and after
}

-- Extract the selected text for better matching across commits
local function get_selected_text()
  local start_line, _ = unpack(api.nvim_buf_get_mark(0, "<"))
  local end_line, _ = unpack(api.nvim_buf_get_mark(0, ">"))
  return api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
end

-- Get git history for the file
local function get_commit_history_for_file(file_path, max_commits)
  local cmd = string.format(
    'git log --follow --pretty=format:"%%H|%%an|%%ad|%%at|%%B" --date=format:"%%Y-%%m-%%d %%H:%%M:%%S" -n %d -- %s',
    max_commits,
    fn.shellescape(file_path)
  )

  local output = fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    api.nvim_err_writeln("Git log failed: " .. output)
    return nil
  end

  local commits = {}
  for commit_data in output:gmatch("([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.-)[\n]*---GIT-EVOLUTION-SEPARATOR---[\n]*") do
    local hash, author, date, timestamp, message = commit_data:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.+)")

    if hash then
      table.insert(commits, {
        hash = hash,
        author = author:gsub("^%s+", ""):gsub("%s+$", ""), -- Trim whitespace
        date = date,
        timestamp = tonumber(timestamp),
        summary = message:gsub("\n+$", ""), -- Trim trailing newlines
      })
    end
  end

  -- Process the output differently
  for commit_block in output:gmatch("(.-)\n\n") do
    local hash, author, date, timestamp, rest = commit_block:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)")

    if hash then
      -- Extract multi-line message
      local message = rest:gsub("^|", "")

      table.insert(commits, {
        hash = hash,
        author = author:gsub("^%s+", ""):gsub("%s+$", ""), -- Trim whitespace
        date = date,
        timestamp = tonumber(timestamp),
        summary = message:gsub("\n+$", ""), -- Trim trailing newlines
      })
    end
  end

  -- Sort by timestamp (newest first)
  table.sort(commits, function(a, b)
    return a.timestamp > b.timestamp
  end)

  return commits
end

-- Get the file content at a specific commit
local function get_file_at_commit(file_path, commit_hash)
  -- Get relative path to the repository root
  local repo_root_cmd = "git rev-parse --show-toplevel"
  local repo_root = fn.system(repo_root_cmd):gsub("\n", "")

  local relative_path = fn.fnamemodify(file_path, ":.")

  -- Get file content at commit
  local cmd = string.format("git show %s:%s", commit_hash, fn.shellescape(relative_path))

  local output = fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    -- Try alternative approach if the first fails
    cmd = string.format("git show %s:%s", commit_hash, fn.shellescape(fn.fnamemodify(file_path, ":t")))
    output = fn.system(cmd)

    if vim.v.shell_error ~= 0 then
      api.nvim_err_writeln("Git show failed: " .. output)
      return nil
    end
  end

  return vim.split(output, "\n")
end

-- Find code in a previous version using approximate text matching
local function find_matching_lines(source_text, target_lines)
  if not target_lines or #target_lines == 0 or #source_text == 0 then
    return nil, nil
  end

  -- Convert source text to a simple pattern for matching
  local pattern_lines = {}
  for _, line in ipairs(source_text) do
    -- Escape magic characters and create a pattern that can handle some differences
    local pattern = line:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    -- Make the pattern more flexible
    pattern = pattern:gsub("%s+", "%%s+") -- Allow different whitespace
    table.insert(pattern_lines, pattern)
  end

  -- Try to find exact matches first
  for i = 1, #target_lines - #source_text + 1 do
    local all_match = true
    for j = 1, #source_text do
      if not target_lines[i + j - 1]:match(pattern_lines[j]) then
        all_match = false
        break
      end
    end

    if all_match then
      return i, i + #source_text - 1
    end
  end

  -- If exact match fails, try to find the most similar section
  local best_match_score = 0
  local best_match_start = nil
  local best_match_end = nil

  for i = 1, #target_lines - #source_text + 1 do
    local match_score = 0
    for j = 1, #source_text do
      local target_line = target_lines[i + j - 1]
      local source_line = source_text[j]

      -- Simple similarity measure: count matching characters
      local match_count = 0
      for k = 1, math.min(#source_line, #target_line) do
        if source_line:sub(k, k) == target_line:sub(k, k) then
          match_count = match_count + 1
        end
      end

      match_score = match_score + match_count / math.max(#source_line, #target_line)
    end

    if match_score > best_match_score then
      best_match_score = match_score
      best_match_start = i
      best_match_end = i + #source_text - 1
    end
  end

  return best_match_start, best_match_end
end

-- Show evolution of selected code
function M.show_code_evolution()
  local start_line, _ = unpack(api.nvim_buf_get_mark(0, "<"))
  local end_line, _ = unpack(api.nvim_buf_get_mark(0, ">"))

  -- Ensure we have valid line numbers
  if not start_line or not end_line or start_line < 1 or end_line < 1 then
    api.nvim_err_writeln("Invalid selection. Please select some text first.")
    return
  end

  -- Get current file path
  local file_path = fn.expand("%:p")

  -- Get selected text for matching in older versions
  local selected_text = get_selected_text()
  if #selected_text == 0 then
    api.nvim_err_writeln("No text selected.")
    return
  end

  -- Get git history for this file
  local commits = get_commit_history_for_file(file_path, config.commit_count)
  if not commits or #commits == 0 then
    api.nvim_err_writeln("Could not retrieve git history for the file.")
    return
  end

  -- Create a new buffer for the evolution view
  local buf = api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.8)

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  })

  -- Prepare content
  local content = { "# Code Evolution History", "" }

  for _, commit in ipairs(commits) do
    -- Add commit header
    table.insert(content, string.format("## %s (%s)", commit.date, commit.hash:sub(1, 7)))
    table.insert(content, string.format("Author: %s", commit.author))

    -- Process multi-line commit summaries
    table.insert(content, "Summary:")
    for _, line in ipairs(vim.split(commit.summary, "\n")) do
      if line ~= "" then
        table.insert(content, "    " .. line)
      else
        table.insert(content, "")
      end
    end

    table.insert(content, "")

    -- Get the full file content at this commit
    local file_content = get_file_at_commit(file_path, commit.hash)
    if file_content and #file_content > 0 then
      -- Find matching lines in this version of the file
      local match_start, match_end = find_matching_lines(selected_text, file_content)

      if match_start and match_end then
        -- Get context if enabled
        local context_start = match_start
        local context_end = match_end

        if config.include_context then
          context_start = math.max(1, match_start - config.context_lines)
          context_end = math.min(#file_content, match_end + config.context_lines)
        end

        table.insert(content, "```")
        for i = context_start, context_end do
          local prefix = (i >= match_start and i <= match_end) and "→ " or "  "
          if i <= #file_content then
            table.insert(content, string.format("%s%3d: %s", prefix, i, file_content[i]))
          end
        end
        table.insert(content, "```")
      else
        table.insert(content, "```")
        table.insert(content, "[Could not locate matching code in this commit]")
        table.insert(content, "```")
      end
    else
      table.insert(content, "```")
      table.insert(content, "[File content not available at this commit]")
      table.insert(content, "```")
    end

    table.insert(content, "")
    table.insert(content, "---")
    table.insert(content, "")
  end

  -- Set buffer content
  api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.bo[buf].filetype = "markdown"

  -- Set up key mappings
  vim.keymap.set("n", "q", function()
    api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true })

  -- Set up function to show diff for a commit when pressing Enter
  vim.keymap.set("n", "<CR>", function()
    local line = api.nvim_get_current_line()
    local hash = line:match("%((%x+)%)")

    if hash then
      -- Close the current window
      api.nvim_win_close(win, true)

      -- Open git show for the commit
      vim.cmd(string.format("silent !git show %s", hash))
      vim.cmd("redraw!")
    end
  end, { buffer = buf, noremap = true })
end

-- Show git history for the current file
function M.show_file_history()
  local file_path = fn.expand("%:p")
  local cmd = string.format(
    'git log --follow --pretty=format:"%%h|%%an|%%ad|%%s" --date=short -n %d -- %s',
    config.commit_count * 2,
    fn.shellescape(file_path)
  )

  local output = fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    api.nvim_err_writeln("Git log failed: " .. output)
    return
  end

  local history = {}
  for line in output:gmatch("[^\r\n]+") do
    local hash, author, date, summary = line:match("([^|]+)|([^|]+)|([^|]+)|(.+)")
    if hash then
      table.insert(history, {
        hash = hash,
        author = author,
        date = date,
        summary = summary,
      })
    end
  end

  -- Create a new buffer for the history view
  local buf = api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.7)

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  })

  -- Prepare content
  local content = { string.format("# File History: %s", fn.expand("%:t")), "" }

  for _, entry in ipairs(history) do
    table.insert(
      content,
      string.format("- %s: %s (%s by %s)", entry.date, entry.summary, entry.hash:sub(1, 7), entry.author)
    )
  end

  -- Set buffer content
  api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.bo[buf].filetype = "markdown"

  -- Set up key mappings
  vim.keymap.set("n", "q", function()
    api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true })

  -- Set up function to show diff for a commit when pressing Enter
  vim.keymap.set("n", "<CR>", function()
    local line = api.nvim_get_current_line()
    local hash = line:match("%((%x+)%)")

    if hash then
      -- Close the current window
      api.nvim_win_close(win, true)

      -- Show the diff
      vim.cmd(string.format("silent !git show %s", hash))
      vim.cmd("redraw!")
    end
  end, { buffer = buf, noremap = true })
end

-- Setup the plugin
function M.setup(opts)
  opts = opts or {}

  -- Update config with user options
  if opts.commit_count then
    config.commit_count = opts.commit_count
  end
  if opts.include_context ~= nil then
    config.include_context = opts.include_context
  end
  if opts.context_lines then
    config.context_lines = opts.context_lines
  end

  -- Set up commands
  vim.api.nvim_create_user_command("GitCodeEvolution", function()
    M.show_code_evolution()
  end, { range = true })

  vim.api.nvim_create_user_command("GitFileHistory", function()
    M.show_file_history()
  end, {})

  -- Optional keymaps
  if opts.keymaps ~= false then
    vim.keymap.set("v", "<leader>ge", M.show_code_evolution, { noremap = true })
    vim.keymap.set("n", "<leader>gh", M.show_file_history, { noremap = true })
  end
end

return M
