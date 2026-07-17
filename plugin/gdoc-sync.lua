-- gdoc-sync.nvim plugin entrypoint.
-- Registers :Gdoc even if the user never calls setup(). The real modules are
-- lazy-loaded on first use, so startup cost is essentially zero.

if vim.g.loaded_gdoc_sync == 1 then
  return
end
vim.g.loaded_gdoc_sync = 1

if vim.fn.has("nvim-0.9") ~= 1 then
  vim.notify("gdoc-sync.nvim requires Neovim >= 0.9", vim.log.levels.ERROR)
  return
end

vim.api.nvim_create_user_command("Gdoc", function(cmd_opts)
  local ok, commands = pcall(require, "gdoc-sync.commands")
  if not ok then
    vim.notify("gdoc-sync.nvim: failed to load — " .. tostring(commands), vim.log.levels.ERROR)
    return
  end
  commands.dispatch(cmd_opts)
end, {
  nargs = "*",
  complete = function(arglead, cmdline, cursorpos)
    local ok, commands = pcall(require, "gdoc-sync.commands")
    if not ok then
      return {}
    end
    return commands.complete(arglead, cmdline, cursorpos)
  end,
  desc = "Sync the current markdown buffer with Google Docs (gdoc-sync CLI)",
})
