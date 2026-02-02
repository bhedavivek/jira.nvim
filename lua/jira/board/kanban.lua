local state = require("jira.board.state")
local ui = require("jira.board.ui")

local M = {}

local COL_WIDTH = 28
local COL_GAP = 2

---Group issues by status, mapped to columns
---@param issues JiraIssueNode[]
---@param columns table[]
---@return table<string, JiraIssueNode[]>
local function group_by_column(issues, columns)
  -- Build status -> column name map
  local status_to_col = {}
  for _, col in ipairs(columns) do
    for _, status_name in ipairs(col.status_names or {}) do
      status_to_col[status_name] = col.name
    end
  end

  local grouped = {}
  for _, col in ipairs(columns) do
    grouped[col.name] = {}
  end

  -- Flatten tree and group
  local function collect(nodes)
    for _, node in ipairs(nodes) do
      local col_name = status_to_col[node.status]
      if col_name and grouped[col_name] then
        table.insert(grouped[col_name], node)
      end
      if node.children then
        collect(node.children)
      end
    end
  end
  collect(issues)

  return grouped
end

---Truncate string to fit width
local function truncate(str, max)
  if vim.fn.strdisplaywidth(str) <= max then
    return str
  end
  return vim.fn.strcharpart(str, 0, max - 1) .. "…"
end

---Wrap text into multiple lines
---@param str string
---@param max_width number
---@param max_lines number
---@return string[]
local function wrap_text(str, max_width, max_lines)
  local lines = {}
  local remaining = str
  while #lines < max_lines and #remaining > 0 do
    if vim.fn.strdisplaywidth(remaining) <= max_width then
      table.insert(lines, remaining)
      remaining = ""
    else
      -- Find break point
      local break_at = max_width
      for i = max_width, 1, -1 do
        local char = remaining:sub(i, i)
        if char == " " then
          break_at = i
          break
        end
      end
      local line = remaining:sub(1, break_at):gsub("%s+$", "")
      table.insert(lines, line)
      remaining = remaining:sub(break_at + 1):gsub("^%s+", "")
    end
  end
  -- Truncate last line if there's more text
  if #remaining > 0 and #lines == max_lines then
    lines[max_lines] = truncate(lines[max_lines] .. " " .. remaining, max_width)
  end
  -- Pad to max_lines
  while #lines < max_lines do
    table.insert(lines, "")
  end
  return lines
end

---Render kanban board
---@param issues JiraIssueNode[]
---@param columns table[]
function M.render(issues, columns)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local grouped = group_by_column(issues, columns)
  local col_count = #columns
  local win_width = vim.api.nvim_win_get_width(state.win or 0)

  -- Calculate column width based on available space
  local total_gap = (col_count - 1) * COL_GAP + 4
  local available = win_width - total_gap
  local col_width = math.max(20, math.floor(available / col_count))

  -- Find max rows needed
  local max_rows = 0
  for _, col in ipairs(columns) do
    local count = #(grouped[col.name] or {})
    -- Each issue takes 3 lines (border, content, border) + 1 gap
    max_rows = math.max(max_rows, count * 4)
  end

  -- Build lines
  local lines = {}
  local hls = {}

  -- Header row
  local header = "  "
  for i, col in ipairs(columns) do
    local name = truncate(col.name, col_width - 2)
    local count = #(grouped[col.name] or {})
    local label = (" %s (%d) "):format(name, count)
    local pad = col_width - vim.fn.strdisplaywidth(label)
    local start_col = #header
    header = header .. label .. (" "):rep(pad)
    if i < col_count then
      header = header .. (" "):rep(COL_GAP)
    end
    table.insert(hls, { row = 0, start_col = start_col, end_col = start_col + #label, hl = "Title" })
  end
  table.insert(lines, header)
  table.insert(lines, "")

  -- Reset line_map
  state.line_map = {}

  -- Render cards row by row
  local row_idx = 0
  local more = true
  local TITLE_LINES = 3
  while more do
    more = false
    local card_top = "  "
    local card_key = "  "
    local card_titles = {}
    for t = 1, TITLE_LINES do card_titles[t] = "  " end
    local card_bottom = "  "
    local key_hls = {}

    for i, col in ipairs(columns) do
      local issues_in_col = grouped[col.name] or {}
      local issue = issues_in_col[row_idx + 1]

      if issue then
        more = true
        local key = truncate(issue.key, col_width - 4)
        local title_lines = wrap_text(issue.summary or "", col_width - 4, TITLE_LINES)
        local status_hl = ui.get_status_hl(issue.status)

        -- Top border
        card_top = card_top .. "┌" .. ("─"):rep(col_width - 2) .. "┐"
        -- Key line
        local key_start = #card_key + 4
        local key_line = "│ " .. key .. (" "):rep(col_width - 4 - #key) .. " │"
        card_key = card_key .. key_line
        -- Title lines
        for t = 1, TITLE_LINES do
          local title = title_lines[t] or ""
          local title_pad = col_width - 4 - vim.fn.strdisplaywidth(title)
          card_titles[t] = card_titles[t] .. "│ " .. title .. (" "):rep(title_pad) .. " │"
        end
        -- Bottom border
        card_bottom = card_bottom .. "└" .. ("─"):rep(col_width - 2) .. "┘"

        -- Track line mapping (key line)
        local line_num = #lines + 1
        state.line_map[line_num] = issue

        table.insert(key_hls, { start_col = key_start, end_col = key_start + #key, hl = status_hl })
      else
        -- Empty space
        local empty = (" "):rep(col_width)
        card_top = card_top .. empty
        card_key = card_key .. empty
        for t = 1, TITLE_LINES do card_titles[t] = card_titles[t] .. empty end
        card_bottom = card_bottom .. empty
        table.insert(key_hls, nil)
      end

      if i < col_count then
        card_top = card_top .. (" "):rep(COL_GAP)
        card_key = card_key .. (" "):rep(COL_GAP)
        for t = 1, TITLE_LINES do card_titles[t] = card_titles[t] .. (" "):rep(COL_GAP) end
        card_bottom = card_bottom .. (" "):rep(COL_GAP)
      end
    end

    if more then
      table.insert(lines, card_top)
      table.insert(lines, card_key)
      local key_row = #lines - 1
      for _, h in ipairs(key_hls) do
        if h then
          table.insert(hls, { row = key_row, start_col = h.start_col, end_col = h.end_col, hl = h.hl })
        end
      end
      for t = 1, TITLE_LINES do table.insert(lines, card_titles[t]) end
      table.insert(lines, card_bottom)
      table.insert(lines, "")
      row_idx = row_idx + 1
    end
  end

  -- Write to buffer
  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  -- Apply highlights
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(state.buf, state.ns, h.row, h.start_col, {
      end_col = h.end_col,
      hl_group = h.hl,
    })
  end
end

return M
