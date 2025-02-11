-- =========================================================================
--  buffy: Switch buffers with <Tab>/<S-Tab> and show a popup.
-- =========================================================================
---@class Config
local config = {
  popup_win = nil,
  popup_buf = nil,
  diewait = 2000,
}

---@class MyModule
local M = {}

---@type Config
M.config = config

local function shorten_path(path)
  -- Remove CWD from the front of path if possible.
  -- ":." transforms the path into a relative path (if within the CWD).
  return vim.fn.fnamemodify(path, ":.")
end

-- Create or update a floating window in the bottom-right corner, listing all buffers.
function M.show_popup(listed_bufs, current_idx)
  -- If a previous popup window exists, close it before creating a new one.
  if M.config.popup_win and vim.api.nvim_win_is_valid(M.config.popup_win) then
    vim.api.nvim_win_close(M.config.popup_win, true)
  end
  if M.timer then
    M.timer:stop()
    M.timer = nil
  end

  -- Prepare display lines
  local display_lines = {}
  for i, buf_nr in ipairs(listed_bufs) do
    local bufname = vim.api.nvim_buf_get_name(buf_nr)
    if bufname == "" then
      bufname = "[No Name]"
    else
      bufname = shorten_path(bufname)
    end

    if i == current_idx then
      table.insert(display_lines, "> " .. bufname)
    else
      table.insert(display_lines, "  " .. bufname)
    end
  end

  -- Create a new scratch buffer (no file on disk)
  local buf = vim.api.nvim_create_buf(false, true)
  M.config.popup_buf = buf

  -- Set lines in the buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

  -- Calculate width/height from the display lines
  local width = 0
  for _, line in ipairs(display_lines) do
    local line_width = #line
    if line_width > width then
      width = line_width
    end
  end
  local height = #display_lines

  -- Get current dimensions
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  -- Placement
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = editor_height - height - 4,
    col = editor_width - width - 2,
    style = "minimal",
    border = "rounded",
    noautocmd = true,
  }

  local win = vim.api.nvim_open_win(buf, false, win_opts)
  M.config.popup_win = win

  M.timer = vim.defer_fn(function()
    if M.config.popup_win and vim.api.nvim_win_is_valid(M.config.popup_win) then
      vim.api.nvim_win_close(M.config.popup_win, true)
    end
  end, M.config.diewait)
end

---- Switch buffers by a certain direction (e.g. +1 or -1).
function M.switch_buffer(direction)
  local current_buf = vim.api.nvim_get_current_buf()
  local all_bufs = vim.api.nvim_list_bufs()

  -- Get all listed buffers
  local listed_bufs = {}
  for _, b in ipairs(all_bufs) do
    if vim.api.nvim_get_option_value("buflisted", { buf = b }) then
      table.insert(listed_bufs, b)
    end
  end

  -- Find current buffer index in the list
  local idx = nil
  for i, b in ipairs(listed_bufs) do
    if b == current_buf then
      idx = i
      break
    end
  end
  if not idx then
    return
  end

  -- Compute the new index; wrap with modulo
  local new_idx = (idx + direction - 1) % #listed_bufs + 1
  local new_buf = listed_bufs[new_idx]
  if new_buf then
    vim.cmd("buffer " .. new_buf)
    M.show_popup(listed_bufs, new_idx)
  end
end

M.setup = function(args)
  local key_opts = { noremap = true, silent = true }
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
  vim.keymap.set("n", "<Tab>", function()
    M.switch_buffer(1)
  end, key_opts)
  vim.keymap.set("n", "<S-Tab>", function()
    M.switch_buffer(-1)
  end, key_opts)
end

return M
