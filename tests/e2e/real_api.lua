-- Real-API E2E, driven by tests/e2e/real-api.sh.
-- Uses an isolated CLI config ($E2E_CONFIG) whose state_file is a temp path,
-- so the user's real mappings are never touched. The wrapper script trashes
-- the created doc afterward.

local failed = 0
local function check(cond, name, detail)
  if cond then
    print("OK  " .. name)
  else
    print("FAIL " .. name .. (detail and (": " .. detail) or ""))
    failed = failed + 1
  end
end

-- Capture notifications so we can wait on command completion.
local messages = {}
vim.notify = function(msg, ...)
  table.insert(messages, msg)
  io.stdout:write("[notify] " .. msg:gsub("\n", " | ") .. "\n")
end

local function wait_msg(pat, ms)
  local ok = vim.wait(ms or 90000, function()
    for _, m in ipairs(messages) do
      if m:lower():find(pat) then
        return true
      end
    end
    return false
  end, 50)
  return ok
end

local function msgs_have(pat)
  for _, m in ipairs(messages) do
    if m:lower():find(pat) then
      return true
    end
  end
  return false
end

local e2e_config = assert(os.getenv("E2E_CONFIG"), "E2E_CONFIG not set")
local work = assert(os.getenv("E2E_WORK"), "E2E_WORK not set")

require("gdoc-sync").setup({ config_file = e2e_config })

local md = work .. "/gdoc-sync-nvim-e2e.md"
local f = assert(io.open(md, "w"))
f:write("# gdoc-sync.nvim E2E\n\nCreated by the plugin test suite. Safe to delete.\n")
f:close()
vim.cmd("edit " .. md)

local gdoc = require("gdoc-sync")

-- 1. create (private; no clipboard via config)
gdoc.create({ "--private", "--no-copy" })
check(wait_msg("created"), "create completes")
check(msgs_have("docs%.google%.com/document/d/"), "create reports a doc URL")

-- links cache should now know the file
vim.wait(15000, function()
  return require("gdoc-sync.links").is_linked(md)
end, 100)
check(require("gdoc-sync.links").is_linked(md), "links cache sees new mapping")
check(require("gdoc-sync.statusline").component() ~= "", "statusline lights up")

-- 2. push an edit
vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "A pushed line." })
gdoc.push({})
check(wait_msg("pushed"), "push completes")

-- 3. pull round-trips
messages = {}
gdoc.pull()
check(wait_msg("pulled"), "pull completes")
local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
check(content:find("A pushed line", 1, true) ~= nil, "pulled content contains the pushed line", content)

-- 4. diff: local == remote right after a pull
messages = {}
gdoc.diff()
check(wait_msg("no differences"), "diff reports in-sync")

-- 5. status float renders
messages = {}
gdoc.status({})
vim.wait(30000, function()
  return vim.bo.buftype == "nofile"
end, 50)
check(vim.bo.buftype == "nofile", "status opens a float")
local status_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
check(status_text:find("gdoc%-sync%-nvim%-e2e") ~= nil, "status lists the test file", status_text)
pcall(vim.cmd, "close")

-- Save the doc id for the wrapper's cleanup BEFORE unlink forgets it.
local doc_id = require("gdoc-sync.links").doc_id(md)
if doc_id then
  local idf = assert(io.open(work .. "/doc_id", "w"))
  idf:write(doc_id)
  idf:close()
end

-- 6. unlink
messages = {}
vim.cmd("edit " .. md)
gdoc.unlink()
check(wait_msg("unlinked"), "unlink completes")

os.exit(failed == 0 and 0 or 1)
