-- lua/plugins/git_code_evolution.lua
local api = vim.api
local fn = vim.fn

local M = {}
local config = {
  commit_count = 5, -- Default number of commits to show
  include_context = true, -- Show surrounding lines for context
  context_lines = 3, -- Number of context lines before and after
}

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
  local relative_path = fn.fnamemodify(file_path, ":.")

  -- Get file content at commit
  local cmd = string.format("git show %s:%s", commit_hash, fn.shellescape(relative_path))

  local output = fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    -- Try alternative approach if the first fails
    cmd = string.format("git show %s:%s", commit_hash, fn.shellescape(fn.fnamemodify(file_path, ":t")))
    output = fn.system(cmd)

    if vim.v.shell_error ~= 0 then
      return nil
    end
  end

  return vim.split(output, "\n")
end

-- Get previous commit for a specific commit
local function get_previous_commit(commit_hash)
  if commit_hash == "0000000000000000000000000000000000000000" then
    return nil
  end

  local cmd = string.format("git rev-parse %s^", commit_hash)
  local output = fn.system(cmd):gsub("\n", "")

  if vim.v.shell_error ~= 0 then
    return nil
  end

  return output
end

-- Determine if a commit was an addition, deletion, or modification
local function determine_change_type(file_path, commit_hash, lines)
  local prev_commit = get_previous_commit(commit_hash)
  if not prev_commit then
    return "addition", nil -- If no previous commit, it's an addition
  end

  -- Check if file existed in previous commit
  local check_file_cmd =
    string.format("git ls-tree --name-only %s %s", prev_commit, fn.shellescape(fn.fnamemodify(file_path, ":.")))
  local check_file_output = fn.system(check_file_cmd):gsub("\n", "")

  if check_file_output == "" then
    return "addition", nil -- File didn't exist before
  end

  -- Get diff to determine if lines were added, deleted, or modified
  local diff_cmd = string.format("git show %s -- %s", commit_hash, fn.shellescape(file_path))
  local diff_output = fn.system(diff_cmd)

  -- Extract source line numbers from the lines we're looking at
  local source_lines = {}
  for _, line_info in ipairs(lines) do
    table.insert(source_lines, line_info.source_line)
  end

  -- Look for addition markers in the diff
  local has_additions = false
  local has_deletions = false

  -- Simplified check - not perfect but gives a good indication
  for line in diff_output:gmatch("[^\r\n]+") do
    -- Check for additions (lines starting with +)
    if line:match("^%+") then
      has_additions = true
    end

    -- Check for deletions (lines starting with -)
    if line:match("^%-") then
      has_deletions = true
    end
  end

  if has_additions and has_deletions then
    return "modification", prev_commit
  elseif has_additions then
    return "addition", prev_commit
  elseif has_deletions then
    return "deletion", prev_commit
  else
    return "unknown", prev_commit
  end
end

-- Get the section of code from a file at a specific commit
local function get_code_section(file_content, min_line, max_line, context_lines)
  if not file_content or #file_content == 0 then
    return {}
  end

  local context_start = math.max(1, min_line - (context_lines or 0))
  local context_end = math.min(#file_content, max_line + (context_lines or 0))

  local section = {}
  for i = context_start, context_end do
    if i <= #file_content then
      table.insert(section, {
        line_num = i,
        content = file_content[i],
        is_selected = (i >= min_line and i <= max_line),
      })
    end
  end

  return section
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

  -- Limit to configured number of commits
  if #commits > config.commit_count then
    commits = { unpack(commits, 1, config.commit_count) }
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

  -- Get current version of the code
  local current_code = api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  table.insert(content, "## Current Version")
  table.insert(content, "")
  table.insert(content, "```")
  for i, line in ipairs(current_code) do
    table.insert(content, string.format("%3d: %s", start_line + i - 1, line))
  end
  table.insert(content, "```")
  table.insert(content, "")

  -- For each commit that affected the selection
  for _, commit in ipairs(commits) do
    -- Skip commits with hash 0000000 (uncommitted changes)
    if commit.hash == "0000000000000000000000000000000000000000" then
      goto continue
    end

    local commit_date = string.format("%s %s", commit.date, commit.time)
    table.insert(content, string.format("## %s (%s)", commit_date, commit.hash:sub(1, 7)))
    table.insert(content, string.format("Author: %s", commit.author))

    -- Add multi-line commit summary
    table.insert(content, "Summary:")
    for _, line in ipairs(vim.split(commit.summary, "\n")) do
      if line ~= "" then
        table.insert(content, "    " .. line)
      else
        table.insert(content, "")
      end
    end
    table.insert(content, "")

    -- Find min and max source lines
    local min_source_line = math.huge
    local max_source_line = 0
    for _, line_info in ipairs(commit.lines) do
      min_source_line = math.min(min_source_line, line_info.source_line)
      max_source_line = math.max(max_source_line, line_info.source_line)
    end

    -- Determine the type of change this commit made to the selected code
    local change_type, prev_commit = determine_change_type(file_path, commit.hash, commit.lines)

    -- Get the code section after this commit
    local after_content = get_file_at_commit(file_path, commit.hash)
    local after_section = get_code_section(
      after_content,
      min_source_line,
      max_source_line,
      config.include_context and config.context_lines or 0
    )

    -- Handle different change types intelligently
    if change_type == "addition" then
      table.insert(content, "### 🟢 Code Added in This Commit:")

      if #after_section > 0 then
        table.insert(content, "```")
        for _, line in ipairs(after_section) do
          local prefix = line.is_selected and "→ " or "  "
          table.insert(content, string.format("%s%3d: %s", prefix, line.line_num, line.content))
        end
        table.insert(content, "```")
        table.insert(content, "")
        table.insert(content, "This code was newly added in this commit.")
      else
        table.insert(content, "```")
        table.insert(content, "[Could not retrieve added code]")
        table.insert(content, "```")
      end
    elseif change_type == "deletion" then
      table.insert(content, "### 🔴 Code Deleted in This Commit:")

      -- Get before state
      if prev_commit then
        local before_content = get_file_at_commit(file_path, prev_commit)
        local before_section = get_code_section(
          before_content,
          min_source_line,
          max_source_line,
          config.include_context and config.context_lines or 0
        )

        if #before_section > 0 then
          table.insert(content, "```")
          for _, line in ipairs(before_section) do
            local prefix = line.is_selected and "→ " or "  "
            table.insert(content, string.format("%s%3d: %s", prefix, line.line_num, line.content))
          end
          table.insert(content, "```")
          table.insert(content, "")
          table.insert(content, "This code was removed in this commit.")
        else
          table.insert(content, "```")
          table.insert(content, "[Could not retrieve deleted code]")
          table.insert(content, "```")
        end
      end
    elseif change_type == "modification" then
      table.insert(content, "### 🔄 Code Modified in This Commit:")

      -- Show after state
      if #after_section > 0 then
        table.insert(content, "#### After:")
        table.insert(content, "```")
        for _, line in ipairs(after_section) do
          local prefix = line.is_selected and "→ " or "  "
          table.insert(content, string.format("%s%3d: %s", prefix, line.line_num, line.content))
        end
        table.insert(content, "```")
      else
        table.insert(content, "#### After:")
        table.insert(content, "```")
        table.insert(content, "[Could not retrieve code after change]")
        table.insert(content, "```")
      end

      -- Get before state
      if prev_commit then
        local before_content = get_file_at_commit(file_path, prev_commit)
        local before_section = get_code_section(
          before_content,
          min_source_line,
          max_source_line,
          config.include_context and config.context_lines or 0
        )

        if #before_section > 0 then
          table.insert(content, "")
          table.insert(content, "#### Before:")
          table.insert(content, "```")
          for _, line in ipairs(before_section) do
            local prefix = line.is_selected and "→ " or "  "
            table.insert(content, string.format("%s%3d: %s", prefix, line.line_num, line.content))
          end
          table.insert(content, "```")
        else
          table.insert(content, "")
          table.insert(content, "#### Before:")
          table.insert(content, "```")
          table.insert(content, "[Could not retrieve code before change]")
          table.insert(content, "```")
        end
      end
    else
      -- Unknown change type, show basic info
      table.insert(content, "### Code in This Commit:")

      if #after_section > 0 then
        table.insert(content, "```")
        for _, line in ipairs(after_section) do
          local prefix = line.is_selected and "→ " or "  "
          table.insert(content, string.format("%s%3d: %s", prefix, line.line_num, line.content))
        end
        table.insert(content, "```")
      else
        table.insert(content, "```")
        table.insert(content, "[Could not retrieve code for this commit]")
        table.insert(content, "```")
      end
    end

    table.insert(content, "")
    table.insert(content, "---")
    table.insert(content, "")

    ::continue::
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
