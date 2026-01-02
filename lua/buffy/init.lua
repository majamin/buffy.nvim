-- =========================================================================
--  buffy: Switch buffers visually
-- =========================================================================

local M = {}

local config = {
  timeout = 2000,
  border = "rounded",
  padding_left = 1,
  padding_right = 1,
  position = "bottom-right",
  show_buffer_numbers = true,
  show_modified_indicator = true,
}

local popup_win = nil
local popup_buf = nil
local timer = nil
local highlights_setup = false

--- Setup highlight groups for the popup
local function setup_highlights()
  local highlights = {
    BuffyNormal = { link = "Normal", default = true },
    BuffyCurrent = { link = "Visual", default = true },
    BuffyModified = { link = "WarningMsg", default = true },
    BuffyBorder = { link = "FloatBorder", default = true },
    BuffyBufferNumber = { link = "Comment", default = true },
  }

  for group, opts in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, opts)
  end
end

--- Calculate popup position
---@param width number Popup width
---@param height number Popup height
---@return number row, number col
local function calculate_position(width, height)
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local position = config.position

  local row, col

  if position == "center" then
    row = math.floor((editor_height - height) / 2)
    col = math.floor((editor_width - width) / 2)
  elseif position == "bottom-left" then
    row = editor_height - height - 4
    col = 2
  elseif position == "top-right" then
    row = 2
    col = editor_width - width - 2
  elseif position == "top-left" then
    row = 2
    col = 2
  else
    row = editor_height - height - 4
    col = editor_width - width - 2
  end

  return row, col
end

--- Safely close popup window if it exists
local function close_popup()
  -- Stop and close any active timer
  if timer then
    pcall(function()
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end)
    timer = nil
  end

  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    pcall(vim.api.nvim_win_close, popup_win, true)
  end

  popup_win = nil
  popup_buf = nil
end

--- Create or update a floating window showing all buffers
---@param listed_bufs number[] List of buffer numbers
---@param current_idx number Index of current buffer in the list
local function show_popup(listed_bufs, current_idx)
  -- Ensure highlights are set up
  if not highlights_setup then
    setup_highlights()
    highlights_setup = true
  end

  close_popup()

  if #listed_bufs == 0 then
    return
  end

  -- Prepare display lines with highlights
  local display_lines = {}
  local highlights = {}

  for i, buf_nr in ipairs(listed_bufs) do
    local bufname = vim.api.nvim_buf_get_name(buf_nr)
    if bufname == "" then
      bufname = "[No Name]"
    else
      bufname = vim.fn.fnamemodify(bufname, ":.")
    end

    -- Check if buffer is modified
    local modified = vim.bo[buf_nr].modified
    local modified_indicator = (modified and config.show_modified_indicator) and " [+]" or ""

    local line
    local prefix_len = 0
    if config.show_buffer_numbers then
      local buf_num_str = string.format("%3d ", buf_nr)
      prefix_len = #buf_num_str
      line = buf_num_str
    else
      line = ""
    end

    local marker = i == current_idx and "> " or "  "
    local padding = string.rep(" ", config.padding_left)

    line = padding .. line .. marker .. bufname .. modified_indicator

    table.insert(display_lines, line)

    -- Store highlight information
    table.insert(highlights, {
      line_idx = i - 1,
      is_current = i == current_idx,
      modified = modified,
      buf_num_start = #padding,
      buf_num_end = #padding + prefix_len,
      modified_start = #line - #modified_indicator,
    })
  end

  -- Create a new scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  popup_buf = buf

  -- Set lines in the buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("buffy")
  for _, hl in ipairs(highlights) do
    local line_text = display_lines[hl.line_idx + 1]

    if hl.is_current then
      vim.api.nvim_buf_set_extmark(buf, ns_id, hl.line_idx, 0, {
        end_line = hl.line_idx,
        end_col = #line_text,
        hl_group = "BuffyCurrent",
        hl_eol = true,
      })
    end

    if config.show_buffer_numbers then
      vim.api.nvim_buf_set_extmark(buf, ns_id, hl.line_idx, hl.buf_num_start, {
        end_col = hl.buf_num_end,
        hl_group = "BuffyBufferNumber",
      })
    end

    if hl.modified and config.show_modified_indicator then
      vim.api.nvim_buf_set_extmark(buf, ns_id, hl.line_idx, hl.modified_start, {
        end_line = hl.line_idx,
        end_col = #line_text,
        hl_group = "BuffyModified",
      })
    end
  end

  -- Calculate width/height from the display lines
  local width = 0
  for _, line in ipairs(display_lines) do
    local line_width = vim.fn.strdisplaywidth(line)
    if line_width > width then
      width = line_width
    end
  end
  width = width + config.padding_right
  local height = #display_lines

  local row, col = calculate_position(width, height)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = config.border,
    noautocmd = true,
  }

  local win = vim.api.nvim_open_win(buf, false, win_opts)
  vim.wo[win].winhighlight = "Normal:BuffyNormal,FloatBorder:BuffyBorder"
  popup_win = win

  local t = (vim.uv or vim.loop).new_timer()
  timer = t
  t:start(
    config.timeout,
    0,
    vim.schedule_wrap(function()
      if timer == t and popup_win == win then
        close_popup()
      end
    end)
  )
end

--- Get all listed buffers
---@return number[] List of buffer numbers
local function get_listed_buffers()
  local all_bufs = vim.api.nvim_list_bufs()
  local listed_bufs = {}

  for _, buf in ipairs(all_bufs) do
    -- Use vim.bo for better compatibility across Neovim versions
    if vim.bo[buf].buflisted then
      table.insert(listed_bufs, buf)
    end
  end

  return listed_bufs
end

--- Switch buffers in a given direction
---@param direction number Direction to switch (1 for next, -1 for previous)
local function switch_buffer(direction)
  local current_buf = vim.api.nvim_get_current_buf()
  local listed_bufs = get_listed_buffers()

  if #listed_bufs <= 1 then
    return
  end

  -- Find current buffer index in the list
  local idx = nil
  for i, buf in ipairs(listed_bufs) do
    if buf == current_buf then
      idx = i
      break
    end
  end

  if not idx then
    -- Current buffer not in list, switch to first buffer
    idx = 0
    direction = 1
  end

  -- Compute the new index with wrap-around
  local new_idx = ((idx - 1 + direction) % #listed_bufs) + 1
  local new_buf = listed_bufs[new_idx]

  if new_buf and vim.api.nvim_buf_is_valid(new_buf) then
    local ok, err = pcall(vim.api.nvim_set_current_buf, new_buf)
    if ok then
      show_popup(listed_bufs, new_idx)
    else
      vim.notify("Buffy: Failed to switch buffer: " .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

--- Switch to the next buffer
function M.next()
  switch_buffer(1)
end

--- Switch to the previous buffer
function M.prev()
  switch_buffer(-1)
end

--- Setup function
function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend("force", config, opts)
  end

  if not highlights_setup then
    setup_highlights()
    highlights_setup = true
  end
end

return M
