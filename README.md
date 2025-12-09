# buffy.nvim

A modern, feature-rich Neovim plugin for visual buffer switching with a sleek floating popup.

## Features

- **Visual Buffer List**: See all your buffers in a floating popup while switching
- **Configurable Keymaps**: Default `<Tab>` and `<Shift-Tab>`, or use your own
- **Buffer Numbers**: Optional buffer number display for quick reference
- **Modified Indicators**: See which buffers have unsaved changes with `[+]`
- **Flexible Positioning**: Place popup in corners or center of the screen
- **Syntax Highlighting**: Customizable highlight groups for better visibility
- **Auto-Close**: Popup automatically disappears after a configurable timeout
- **User Commands**: `BuffyNext`, `BuffyPrev`, and `BuffyToggle` for flexibility
- **Full Type Annotations**: Complete LuaLS annotations for better development experience

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'majamin/buffy.nvim',
  opts = {}
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'majamin/buffy.nvim',
  config = function()
    require('buffy').setup()
  end
}
```

## Configuration

### Default Configuration

```lua
require('buffy').setup({
  -- Timeout in milliseconds before popup auto-closes (0 to disable)
  timeout = 2000,

  -- Show buffer numbers in the popup
  show_buffer_numbers = true,

  -- Show [+] indicator for modified buffers
  show_modified_indicator = true,

  -- Show popup when a buffer is deleted
  show_on_delete = true,

  -- Popup position: "bottom-right" | "bottom-left" | "top-right" | "top-left" | "center"
  position = "bottom-right",

  -- Keymap configuration
  mappings = {
    next_buffer = "<Tab>",      -- Next buffer
    prev_buffer = "<S-Tab>",    -- Previous buffer
    enabled = true,             -- Enable default keymaps
  },

  -- Popup styling
  style = {
    border = "rounded",         -- Border style: "none" | "single" | "double" | "rounded" | "solid" | "shadow"
    padding_left = 1,           -- Left padding inside popup
    padding_right = 1,          -- Right padding inside popup
  },
})
```

## Commands

- `:BuffyNext` - Switch to next buffer
- `:BuffyPrev` - Switch to previous buffer
- `:BuffyToggle` - Toggle the buffer list popup

## Highlight Groups

Customize the appearance by overriding these highlight groups:

```lua
-- Link to existing highlight groups (default)
vim.api.nvim_set_hl(0, "BuffyNormal", { link = "Normal" })
vim.api.nvim_set_hl(0, "BuffyCurrent", { link = "Visual" })
vim.api.nvim_set_hl(0, "BuffyModified", { link = "WarningMsg" })
vim.api.nvim_set_hl(0, "BuffyBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "BuffyBufferNumber", { link = "Comment" })

-- Or define custom colors
vim.api.nvim_set_hl(0, "BuffyCurrent", { bg = "#3b4261", fg = "#c0caf5", bold = true })
vim.api.nvim_set_hl(0, "BuffyModified", { fg = "#e0af68", bold = true })
```

## Requirements

- Neovim >= 0.7.0

## License

MIT (see LICENSE)
