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
    local out = vim.trim(vim.fn.system({ cfg.cmd, "--version" }))
    health.ok(("CLI found: %s (%s)"):format(out, vim.fn.exepath(cfg.cmd)))

    -- The plugin drives `watch --json` and `sync`/`resolve`/`restore`, all of
    -- which arrived in 0.6. On an older CLI live sync silently falls back to
    -- the 0.5 behaviour that could lose edits, so this is worth flagging.
    local major, minor = out:match("(%d+)%.(%d+)")
    if major then
      local version = tonumber(major) * 100 + tonumber(minor)
      if version < 6 then
        health.error(("CLI %s.%s is too old — the merge-based two-way sync, "):format(major, minor)
          .. "conflict tracking and automatic backups need >= 0.6",
          { "Upgrade: pipx upgrade gdoc-sync (or nix profile upgrade gdoc-sync)",
            "On 0.5.x, :Gdoc watch can overwrite edits made on the other side." })
      else
        health.ok("CLI supports merge-based two-way sync (>= 0.6)")
      end
    else
      health.warn("could not parse the CLI version from: " .. out)
    end
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

  -- Live-sync state, which is what most "it isn't syncing" reports are about.
  local gdoc = require("gdoc-sync")
  local watching = vim.tbl_keys(gdoc._watchers or {})
  if #watching > 0 then
    health.ok(("%d watcher(s) running"):format(#watching))
  elseif cfg.auto_watch then
    health.info("auto_watch is on; watchers start when you open a linked markdown buffer")
  else
    health.info("no watchers running (auto_watch is off — use :Gdoc watch)")
  end

  local conflicts = vim.tbl_keys(gdoc._conflicts or {})
  if #conflicts > 0 then
    health.warn(("%d file(s) have unresolved conflicts — syncing is paused for them"):format(#conflicts),
      vim.list_extend({ "Review with :Gdoc conflict, then :Gdoc resolve" }, conflicts))
  end

  if not cfg.safe_reload then
    health.warn("safe_reload is off — a buffer with unsaved changes can be "
      .. "overwritten when the watcher rewrites its file")
  end

  health.info("auth/API problems? run in a terminal: gdoc-sync doctor")
end

return M
