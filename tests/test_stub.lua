-- Functional tests against the stub CLI (tests/stub/gdoc-sync).
-- Run via tests/run.sh, which prepends the stub to $PATH and sets $STUB_LOG.

local failed = 0
local function check(cond, name, detail)
  if cond then
    print("OK  " .. name)
  else
    print("FAIL " .. name .. (detail and (": " .. detail) or ""))
    failed = failed + 1
  end
end

local log_path = assert(os.getenv("STUB_LOG"), "STUB_LOG not set")
local work = assert(os.getenv("STUB_WORK"), "STUB_WORK not set")

local function read_log()
  local f = io.open(log_path, "r")
  if not f then
    return {}
  end
  local lines = {}
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()
  return lines
end

local function wait_for(pred, ms)
  return vim.wait(ms or 4000, pred, 10)
end

local function log_has(pat)
  for _, l in ipairs(read_log()) do
    if l:find(pat) then
      return true
    end
  end
  return false
end

require("gdoc-sync").setup({})

-- A markdown file to operate on.
local md = work .. "/note.md"
local f = assert(io.open(md, "w"))
f:write("# Test\n\nhello\n")
f:close()
vim.cmd("edit " .. md)

-- links cache fills from stub status --json (STUB_LINKED = md)
check(wait_for(function()
  return require("gdoc-sync.links").loaded
end), "links cache refresh")
check(require("gdoc-sync.links").is_linked(md), "is_linked(current file)",
  vim.inspect(require("gdoc-sync.links").mappings))
check(require("gdoc-sync.links").doc_url(md)
  == "https://docs.google.com/document/d/STUBDOC123/edit", "doc_url")

-- statusline shows the icon for a linked buffer
local comp = require("gdoc-sync.statusline").component()
check(comp ~= "", "statusline component non-empty", comp)

-- create: argv recorded, notify carries URL
vim.cmd("Gdoc create")
check(wait_for(function()
  return log_has("^create .*note%.md")
end), "create invoked with file")

-- push (no drift): plain push, no --yes
vim.cmd("Gdoc push")
check(wait_for(function()
  return log_has("^push .*note%.md")
end), "push invoked")
check(not log_has("^push %-%-yes"), "push without drift never adds --yes")

-- push with drift: exit 2 -> vim.ui.select -> retry with --yes
vim.env.STUB_DRIFT = "1"
local orig_select = vim.ui.select
vim.ui.select = function(_, _, on_choice)
  on_choice("Overwrite remote")
end
vim.cmd("Gdoc push")
check(wait_for(function()
  return log_has("^push %-%-yes .*note%.md")
end), "drift push retries with --yes after confirm")
vim.ui.select = orig_select
vim.env.STUB_DRIFT = nil

-- pull: file rewritten by CLI, buffer reloaded
vim.cmd("Gdoc pull")
check(wait_for(function()
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  return line == "remote content line"
end), "pull reloads buffer from disk",
  vim.inspect(vim.api.nvim_buf_get_lines(0, 0, 1, false)))

-- diff: exit 1 + output opens a diff split
vim.cmd("Gdoc diff")
check(wait_for(function()
  return vim.bo.filetype == "diff"
end), "diff opens a diff buffer", "ft=" .. vim.bo.filetype)
vim.cmd("close")

-- share sugar: 'view' -> --anyone view; email -> --with
vim.cmd("Gdoc share view")
check(wait_for(function()
  return log_has("^share .*%-%-anyone view")
end), "share view maps to --anyone")
vim.cmd("Gdoc share someone@example.com:edit")
check(wait_for(function()
  return log_has("%-%-with someone@example%.com:edit")
end), "share email maps to --with")

-- export format flag
vim.cmd("Gdoc export pdf")
check(wait_for(function()
  return log_has("^export %-%-format pdf")
end), "export passes --format")

-- unknown subcommand: no crash
local ok = pcall(vim.cmd, "Gdoc bogus")
check(ok, "unknown subcommand handled")

os.exit(failed == 0 and 0 or 1)
