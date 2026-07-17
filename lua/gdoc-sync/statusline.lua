-- Statusline component. Reads the links cache only — never blocks, never
-- touches the network. Empty string for unlinked buffers.
--
--   lualine:  sections = { lualine_x = { require("gdoc-sync.statusline").component } }
--   'statusline': %{%v:lua.require'gdoc-sync.statusline'.component()%}

local M = {}

function M.component()
  local ok, links = pcall(require, "gdoc-sync.links")
  if not ok or not links.loaded then
    return ""
  end
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" or not links.is_linked(name) then
    return ""
  end
  local icon = require("gdoc-sync.config").options.statusline_icon
  local watching = next(require("gdoc-sync")._watchers) ~= nil
  return watching and (icon .. " (watching)") or icon
end

return M
