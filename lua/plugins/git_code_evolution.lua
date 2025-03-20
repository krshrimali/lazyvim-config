-- lua/plugins/git_code_evolution.lua
local api = vim.api
local fn = vim.fn

local M = {}

-- Parse git blame output for a range of lines
local function get_blame_data(file_path, start_line, end_line)
  -- Use standard blame format without -p for cleaner output
  local cmd = string.format("git blame -L %d,%d %s", start_line, end_line, fn.shellescape(file_path))

  local output = fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    api.nvim_err_writeln("Git blame failed: " .. output)
    return nil
  end

  local blame_data = {}

  for line_idx, line in ipairs(vim.split(output, "\n")) do
    if line:match("^%x+") then -- Line starts with commit hash
      -- Format appears to be:
      -- hash (author date time timezone linenum) content
      local commit_hash, author, date, time, timezone, source_line, content =
        line:match("^(%x+)%s+%(([^%d]+)%s+(%d%d%d%d%-%d%d%-%d%d)%s+(%d%d:%d%d:%d%d)%s+([^%s]+)%s+(%d+)%)(.*)$")

      if commit_hash then
        -- Get line number in the current file
        local current_line = start_line + line_idx - 1

        -- Get commit details for this hash if we don't have it already
        if not blame_data[commit_hash] then
          -- Get full commit message (not just the first line)
          local summary_cmd = string.format('git show -s --format="%%B" %s', commit_hash)
          local summary = fn.system(summary_cmd)

          -- Trim trailing newlines but preserve internal newlines for multi-line messages
          summary = summary:gsub("\n+$", "")

          blame_data[commit_hash] = {
            hash = commit_hash,
            author = author:gsub("^%s+", ""):gsub("%s+$", ""), -- Trim whitespace
            date = date,
            time = time,
            timezone = timezone,
            summary = summary,
            timestamp = os.time({
              year = tonumber(date:sub(1, 4)),
              month = tonumber(date:sub(6, 7)),
              day = tonumber(date:sub(9, 10)),
              hour = tonumber(time:sub(1, 2)),
              min = tonumber(time:sub(4, 5)),
              sec = tonumber(time:sub(7, 8)),
            }),
            lines = {},
          }
        end

        -- Add this line to the commit's lines
        table.insert(blame_data[commit_hash].lines, {
          current_line = current_line,
          source_line = tonumber(source_line),
          content = content,
        })
      end
    end
  end

  return blame_data
end

-- Get the file content at a specific commit
local function get_file_at_commit(file_path, commit_hash)
  -- Get relative path to the repository root
  local repo_root_cmd = "git rev-parse --show-toplevel"
  local repo_root = fn.system(repo_root_cmd):gsub("\n", "")

  local relative_path
  if file_path:sub(1, #repo_root) == repo_root then
    relative_path = file_path:sub(#repo_root + 2) -- +2 to account for the trailing slash
  else
    -- Fallback to git ls-files
    local cmd = string.format(
      "git ls-files --full-name --with-tree=%s | grep -F %s",
      commit_hash,
      fn.shellescape(fn.fnamemodify(file_path, ":t"))
    )
    relative_path = fn.system(cmd):gsub("\n", "")

    if relative_path == "" then
      -- Final fallback to just the filename
      relative_path = fn.fnamemodify(file_path, ":t")
    end
  end

  -- Get file content at commit
  local cmd = string.format("git show %s:%s", commit_hash, fn.shellescape(relative_path))

  local output = fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    api.nvim_err_writeln("Git show failed: " .. output)
    return nil
  end

  return vim.split(output, "\n")
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

  -- Get git blame data for the selection
  local blame_data = get_blame_data(file_path, start_line, end_line)
  if not blame_data or vim.tbl_isempty(blame_data) then
    api.nvim_err_writeln("Could not retrieve git blame data for the selection.")
    return
  end

  -- Sort commits by timestamp (newest first)
  local commits = {}
  for _, commit in pairs(blame_data) do
    table.insert(commits, commit)
  end

  table.sort(commits, function(a, b)
    return a.timestamp > b.timestamp
  end)

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
    table.insert(content, string.format("## %s %s (%s)", commit.date, commit.time, commit.hash:sub(1, 7)))
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
      -- Find source line range for this commit
      local min_line = math.huge
      local max_line = 0

      for _, line_info in ipairs(commit.lines) do
        min_line = math.min(min_line, line_info.source_line)
        max_line = math.max(max_line, line_info.source_line)
      end

      -- Track which lines are part of the selected section
      local relevant_lines = {}
      for _, line_info in ipairs(commit.lines) do
        relevant_lines[line_info.source_line] = true
      end

      -- Get context (5 lines before and after)
      local context_start = math.max(1, min_line - 5)
      local context_end = math.min(#file_content, max_line + 5)

      table.insert(content, "```")
      for i = context_start, context_end do
        local prefix = relevant_lines[i] and "→ " or "  "
        if i <= #file_content then
          table.insert(content, string.format("%s%3d: %s", prefix, i, file_content[i]))
        end
      end
      table.insert(content, "```")
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
  local cmd =
    string.format('git log --follow --pretty=format:"%%h|%%an|%%ad|%%s" --date=short -- %s', fn.shellescape(file_path))

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
