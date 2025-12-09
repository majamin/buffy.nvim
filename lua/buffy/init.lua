-- =========================================================================
--  buffy: Switch buffers with <Tab>/<S-Tab> and show a popup.
-- =========================================================================

---@class buffy.Config
---@field timeout number Milliseconds before popup auto-closes (default: 2000)
---@field show_buffer_numbers boolean Show buffer numbers in popup (default: true)
---@field show_modified_indicator boolean Show [+] for modified buffers (default: true)
---@field show_on_delete boolean Show popup when a buffer is deleted (default: true)
---@field position "bottom-right" | "bottom-left" | "top-right" | "top-left" | "center" Popup position (default: "bottom-right")
---@field mappings buffy.Mappings Keymap configuration
---@field style buffy.Style Popup styling configuration

---@class buffy.Mappings
---@field next_buffer string Keymap for next buffer (default: "<Tab>")
---@field prev_buffer string Keymap for previous buffer (default: "<S-Tab>")
---@field enabled boolean Enable default keymaps (default: true)

---@class buffy.Style
---@field border string Border style (default: "rounded")
---@field padding_left number Left padding inside popup (default: 1)
---@field padding_right number Right padding inside popup (default: 1)

---@class buffy.State
---@field popup_win number|nil Current popup window ID
---@field popup_buf number|nil Current popup buffer ID
---@field timer any|nil Active timer for auto-closing popup (vim.defer_fn handle)
---@field config buffy.Config Current configuration

local M = {}

---@type buffy.State
local state = {
  popup_win = nil,
  popup_buf = nil,
  timer = nil,
  config = {
    timeout = 2000,
    show_buffer_numbers = true,
    show_modified_indicator = true,
    show_on_delete = true,
    position = "bottom-right",
    mappings = {
      next_buffer = "<Tab>",
      prev_buffer = "<S-Tab>",
      enabled = true,
    },
    style = {
      border = "rounded",
      padding_left = 1,
      padding_right = 1,
    },
  },
}

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

--- Shorten file path relative to CWD
---@param path string File path to shorten
---@return string Shortened path
local function shorten_path(path)
  return vim.fn.fnamemodify(path, ":.")
end

--- Calculate popup position based on configuration
---@param width number Popup width
---@param height number Popup height
---@return number row, number col
local function calculate_position(width, height)
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local position = state.config.position

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
  else -- bottom-right (default)
    row = editor_height - height - 4
    col = editor_width - width - 2
  end

  return row, col
end

--- Safely close popup window if it exists
local function close_popup()
  -- Stop and close any active timer
  if state.timer then
    pcall(function()
      if not state.timer:is_closing() then
        state.timer:stop()
        state.timer:close()
      end
    end)
    state.timer = nil
  end

  if state.popup_win and vim.api.nvim_win_is_valid(state.popup_win) then
    pcall(vim.api.nvim_win_close, state.popup_win, true)
  end

  state.popup_win = nil
  state.popup_buf = nil
end

--- Create or update a floating window showing all buffers
---@param listed_bufs number[] List of buffer numbers
---@param current_idx number Index of current buffer in the list
function M.show_popup(listed_bufs, current_idx)
  close_popup()

  if #listed_bufs == 0 then
    return
  end

  -- Prepare display lines with highlights
  local display_lines = {}
  local highlights = {}
  local config = state.config

  for i, buf_nr in ipairs(listed_bufs) do
    local bufname = vim.api.nvim_buf_get_name(buf_nr)
    if bufname == "" then
      bufname = "[No Name]"
    else
      bufname = shorten_path(bufname)
    end

    -- Check if buffer is modified
    local modified = vim.bo[buf_nr].modified
    local modified_indicator = (modified and config.show_modified_indicator) and " [+]" or ""

    -- Build line with optional buffer number
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
    local padding = string.rep(" ", config.style.padding_left)

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
  state.popup_buf = buf

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
  width = width + config.style.padding_right
  local height = #display_lines

  -- Calculate position
  local row, col = calculate_position(width, height)

  -- Create window
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = config.style.border,
    noautocmd = true,
  }

  local win = vim.api.nvim_open_win(buf, false, win_opts)
  vim.wo[win].winhighlight = "Normal:BuffyNormal,FloatBorder:BuffyBorder"
  state.popup_win = win

  -- Set up auto-close timer using libuv timer (can be stopped)
  if config.timeout > 0 then
    local timer = (vim.uv or vim.loop).new_timer()
    state.timer = timer
    timer:start(
      config.timeout,
      0,
      vim.schedule_wrap(function()
        -- Only close if this is still the active timer and window
        if state.timer == timer and state.popup_win == win then
          close_popup()
        end
      end)
    )
  end
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
function M.switch_buffer(direction)
  local current_buf = vim.api.nvim_get_current_buf()
  local listed_bufs = get_listed_buffers()

  if #listed_bufs <= 1 then
    -- Only one buffer, nothing to switch to
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
      M.show_popup(listed_bufs, new_idx)
    else
      vim.notify("Buffy: Failed to switch buffer: " .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

--- Refresh the popup if it's currently visible
local function refresh_popup()
  if not state.popup_win or not vim.api.nvim_win_is_valid(state.popup_win) then
    return
  end

  local listed_bufs = get_listed_buffers()
  if #listed_bufs == 0 then
    close_popup()
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local idx = 1

  for i, buf in ipairs(listed_bufs) do
    if buf == current_buf then
      idx = i
      break
    end
  end

  M.show_popup(listed_bufs, idx)
end

--- Setup the plugin with user configuration
---@param opts buffy.Config|nil User configuration options
function M.setup(opts)
  -- Merge user config with defaults
  state.config = vim.tbl_deep_extend("force", state.config, opts or {})

  -- Setup highlights
  setup_highlights()

  -- Setup keymaps if enabled
  if state.config.mappings.enabled then
    local key_opts = { noremap = true, silent = true, desc = "Buffy: Next buffer" }
    vim.keymap.set("n", state.config.mappings.next_buffer, function()
      M.switch_buffer(1)
    end, key_opts)

    key_opts.desc = "Buffy: Previous buffer"
    vim.keymap.set("n", state.config.mappings.prev_buffer, function()
      M.switch_buffer(-1)
    end, key_opts)
  end

  -- Setup commands
  vim.api.nvim_create_user_command("BuffyNext", function()
    M.switch_buffer(1)
  end, { desc = "Switch to next buffer" })

  vim.api.nvim_create_user_command("BuffyPrev", function()
    M.switch_buffer(-1)
  end, { desc = "Switch to previous buffer" })

  vim.api.nvim_create_user_command("BuffyToggle", function()
    if state.popup_win and vim.api.nvim_win_is_valid(state.popup_win) then
      close_popup()
    else
      local listed_bufs = get_listed_buffers()
      local current_buf = vim.api.nvim_get_current_buf()
      local idx = 1
      for i, buf in ipairs(listed_bufs) do
        if buf == current_buf then
          idx = i
          break
        end
      end
      M.show_popup(listed_bufs, idx)
    end
  end, { desc = "Toggle buffer list popup" })

  -- Setup autocmds to refresh popup when buffer list changes
  local augroup = vim.api.nvim_create_augroup("Buffy", { clear = true })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    callback = function(args)
      -- Ignore if it's the popup buffer itself
      if state.popup_buf and args.buf == state.popup_buf then
        return
      end

      -- Small delay to ensure buffer is fully removed before showing popup
      vim.defer_fn(function()
        if state.config.show_on_delete then
          local listed_bufs = get_listed_buffers()
          if #listed_bufs > 0 then
            local current_buf = vim.api.nvim_get_current_buf()
            local idx = 1
            for i, buf in ipairs(listed_bufs) do
              if buf == current_buf then
                idx = i
                break
              end
            end
            M.show_popup(listed_bufs, idx)
          end
        else
          -- If show_on_delete is false, just refresh if already visible
          refresh_popup()
        end
      end, 10)
    end,
    desc = "Show Buffy popup when buffers are deleted",
  })

  -- Also refresh when new buffers are added (only if already visible)
  vim.api.nvim_create_autocmd("BufAdd", {
    group = augroup,
    callback = function(args)
      -- Ignore unlisted buffers (like the popup itself)
      if not vim.bo[args.buf].buflisted then
        return
      end

      -- Ignore if it's the popup buffer
      if state.popup_buf and args.buf == state.popup_buf then
        return
      end

      -- Only refresh if popup is already visible
      vim.defer_fn(refresh_popup, 10)
    end,
    desc = "Refresh Buffy popup when buffers are added",
  })
end

--- Manually close the popup (exposed for user commands)
function M.close_popup()
  close_popup()
end

--- Get the current configuration
---@return buffy.Config
function M.get_config()
  return vim.deepcopy(state.config)
end

return M
