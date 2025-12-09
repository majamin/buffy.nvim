-- Prevent plugin from loading twice
if vim.g.loaded_buffy then
  return
end
vim.g.loaded_buffy = 1

-- Early exit if Neovim version is too old
if vim.fn.has("nvim-0.7.0") == 0 then
  vim.notify("buffy.nvim requires Neovim >= 0.7.0", vim.log.levels.ERROR)
  return
end
