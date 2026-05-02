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
local timer = nil
local highlights_setup = false

local function setup_highlights()
  local highlights = {
    BuffyNormal = { link = "Normal", default = true },
    BuffyCurrent = { link = "Visual", default = true },
    BuffyModified = { link = "WarningMsg", default = true },
    BuffyBorder = { fg = vim.api.nvim_get_hl(0, { name = "FloatBorder" }).fg },
    BuffyDeleted = { fg = vim.api.nvim_get_hl(0, { name = "Comment" }).fg, strikethrough = true },
    BuffyBufferNumber = { link = "Comment", default = true },
  }
  for group, opts in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, opts)
  end
end

---@param width number
---@param height number
---@return number row, number col
local function calculate_position(width, height)
  local ew = vim.o.columns
  local eh = vim.o.lines
  local pos = config.position
  if pos == "center" then
    return math.floor((eh - height) / 2), math.floor((ew - width) / 2)
  elseif pos == "bottom-left" then
    return eh - height - 4, 2
  elseif pos == "top-right" then
    return 2, ew - width - 2
  elseif pos == "top-left" then
    return 2, 2
  else -- bottom-right
    return eh - height - 4, ew - width - 2
  end
end

local function close_popup()
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
end

--- entries: array of buffer numbers (live) or {name=string} tables (deleted stubs)
---@param entries table
---@param current_idx number
local function show_popup(entries, current_idx)
  if not highlights_setup then
    setup_highlights()
    highlights_setup = true
  end

  close_popup()

  if #entries == 0 then return end

  local display_lines = {}
  local highlights = {}
  local padding = string.rep(" ", config.padding_left)

  for i, entry in ipairs(entries) do
    local is_deleted = type(entry) == "table"
    local bufname, modified, buf_nr

    if is_deleted then
      bufname = entry.name
      modified = false
    else
      buf_nr = entry
      bufname = vim.api.nvim_buf_get_name(buf_nr)
      bufname = bufname ~= "" and vim.fn.fnamemodify(bufname, ":.") or "[No Name]"
      modified = vim.bo[buf_nr].modified
    end

    local modified_indicator = (modified and config.show_modified_indicator) and " [+]" or ""
    local line, prefix_len = "", 0
    if config.show_buffer_numbers then
      local num_str = is_deleted and "    " or string.format("%3d ", buf_nr)
      prefix_len = #num_str
      line = num_str
    end

    local marker = i == current_idx and "> " or "  "
    line = padding .. line .. marker .. bufname .. modified_indicator

    table.insert(display_lines, line)
    table.insert(highlights, {
      line_idx = i - 1,
      is_current = i == current_idx,
      is_deleted = is_deleted,
      modified = modified,
      buf_num_start = #padding,
      buf_num_end = #padding + prefix_len,
      modified_start = #line - #modified_indicator,
    })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

  local ns_id = vim.api.nvim_create_namespace("buffy")
  for _, hl in ipairs(highlights) do
    local line_text = display_lines[hl.line_idx + 1]

    if hl.is_current then
      vim.api.nvim_buf_set_extmark(buf, ns_id, hl.line_idx, 0, {
        end_line = hl.line_idx, end_col = #line_text,
        hl_group = "BuffyCurrent", hl_eol = true,
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
        end_line = hl.line_idx, end_col = #line_text,
        hl_group = "BuffyModified",
      })
    end

    if hl.is_deleted then
      vim.api.nvim_buf_set_extmark(buf, ns_id, hl.line_idx, 0, {
        end_line = hl.line_idx, end_col = #line_text,
        hl_group = "BuffyDeleted", hl_eol = true,
      })
    end
  end

  local width = 0
  for _, line in ipairs(display_lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = width + config.padding_right
  local height = #display_lines

  local row, col = calculate_position(width, height)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width, height = height,
    row = row, col = col,
    style = "minimal",
    border = config.border,
    noautocmd = true,
  })
  vim.wo[win].winhighlight = "Normal:BuffyNormal,FloatBorder:BuffyBorder"
  popup_win = win

  local t = (vim.uv or vim.loop).new_timer()
  timer = t
  t:start(config.timeout, 0, vim.schedule_wrap(function()
    if timer == t and popup_win == win then
      close_popup()
    end
  end))
end

---@return number[]
local function get_listed_buffers()
  local listed = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      table.insert(listed, buf)
    end
  end
  return listed
end

---@param direction number 1 for next, -1 for previous
local function switch_buffer(direction)
  local current_buf = vim.api.nvim_get_current_buf()
  local listed = get_listed_buffers()

  if #listed <= 1 then return end

  local idx
  for i, buf in ipairs(listed) do
    if buf == current_buf then idx = i; break end
  end

  if not idx then idx = 0; direction = 1 end

  local new_idx = ((idx - 1 + direction) % #listed) + 1
  local new_buf = listed[new_idx]

  if new_buf and vim.api.nvim_buf_is_valid(new_buf) then
    local ok, err = pcall(vim.api.nvim_set_current_buf, new_buf)
    if ok then
      show_popup(listed, new_idx)
    else
      vim.notify("Buffy: Failed to switch buffer: " .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

function M.next() switch_buffer(1) end
function M.prev() switch_buffer(-1) end

vim.api.nvim_create_autocmd("BufDelete", {
  callback = function(ev)
    local del_buf = ev.buf
    local name = vim.api.nvim_buf_get_name(del_buf)
    name = name ~= "" and vim.fn.fnamemodify(name, ":.") or "[No Name]"
    local snapshot = get_listed_buffers()
    vim.schedule(function()
      local current_buf = vim.api.nvim_get_current_buf()
      local entries = {}
      local current_idx = 1
      for _, buf in ipairs(snapshot) do
        if buf == del_buf then
          table.insert(entries, { name = name })
        elseif vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
          table.insert(entries, buf)
          if buf == current_buf then current_idx = #entries end
        end
      end
      show_popup(entries, current_idx)
    end)
  end,
})

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
