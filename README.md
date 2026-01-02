# buffy.nvim

Buffer switching with a floating popup.

![buffy screenshot](screenshot.png)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'majamin/buffy.nvim',
  opts = {},
  keys = {
    { "<Tab>", function() require('buffy').next() end, desc = "Next buffer" },
    { "<S-Tab>", function() require('buffy').prev() end, desc = "Previous buffer" },
  },
}
```

## Theming

Override highlight groups:

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
