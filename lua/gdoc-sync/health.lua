-- :checkhealth gdoc-sync

local M = {}

function M.check()
  local health = vim.health
  health.start("gdoc-sync.nvim")

  if vim.fn.has("nvim-0.9") == 1 then
    health.ok("Neovim >= 0.9")
  else
    health.error("Neovim >= 0.9 required")
  end

  local cfg = require("gdoc-sync.config").options
  if vim.fn.executable(cfg.cmd) == 1 then
    local out = vim.fn.system({ cfg.cmd, "--version" })
    health.ok(("CLI found: %s (%s)"):format(vim.trim(out), vim.fn.exepath(cfg.cmd)))
  else
    health.error(("%q is not executable"):format(cfg.cmd),
      { "Install the gdoc-sync CLI: https://github.com/MattHandzel/gdoc-sync" })
    return
  end

  if cfg.config_file then
    if vim.fn.filereadable(vim.fn.expand(cfg.config_file)) == 1 then
      health.ok("config_file: " .. cfg.config_file)
    else
      health.warn("config_file not readable: " .. cfg.config_file)
    end
  end

  local links = require("gdoc-sync.links")
  if links.loaded then
    local n = vim.tbl_count(links.mappings)
    health.ok(n .. " linked file(s) in the cache")
  else
    health.info("links cache not loaded yet (fills ~100ms after setup)")
  end

  health.info("auth/API problems? run in a terminal: gdoc-sync doctor")
end

return M
