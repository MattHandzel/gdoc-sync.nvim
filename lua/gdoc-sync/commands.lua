-- :Gdoc subcommand dispatch and completion.

local M = {}

-- subcommand -> { fn = handler name in init.lua, complete = candidates }
local subcommands = {
  create = { complete = { "--private", "--edit", "--view", "--open", "--title" } },
  push = { complete = { "--yes" } },
  pull = {},
  status = { complete = { "--remote" } },
  diff = {},
  open = {},
  share = { complete = { "view", "comment", "edit", "private" } },
  export = { complete = { "pdf", "docx", "odt", "txt", "html", "epub" } },
  link = {},
  unlink = {},
  watch = { complete = { "all", "stop" } },
  doctor = {},
}

local order = {
  "create", "push", "pull", "status", "diff", "open", "share",
  "export", "link", "unlink", "watch", "doctor",
}

local function ensure_setup()
  if not vim.g._gdoc_sync_setup_done then
    require("gdoc-sync").setup({})
    vim.g._gdoc_sync_setup_done = 1
  end
end

function M.dispatch(cmd_opts)
  ensure_setup()
  local args = cmd_opts.fargs or {}
  local sub = table.remove(args, 1)
  if not sub or not subcommands[sub] then
    vim.notify(
      "usage: :Gdoc {" .. table.concat(order, "|") .. "}",
      vim.log.levels.WARN, { title = "gdoc-sync" })
    return
  end
  local gdoc = require("gdoc-sync")
  gdoc[sub](args)
end

function M.complete(arglead, cmdline, _)
  ensure_setup()
  -- Completing the subcommand itself?
  local before = cmdline:sub(1, #cmdline - #arglead)
  if before:match("^%s*Gdoc%s+$") then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, order)
  end
  local sub = cmdline:match("^%s*Gdoc%s+(%S+)")
  local spec = sub and subcommands[sub]
  if spec and spec.complete then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, spec.complete)
  end
  return {}
end

return M
