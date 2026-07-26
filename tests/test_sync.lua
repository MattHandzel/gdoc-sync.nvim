-- Buffer-safety and sync-event tests.
--
-- These cover the editor half of the data-loss bug: what the plugin does when
-- the watcher rewrites a file that is open in a buffer, and how it turns the
-- CLI's JSON events into reloads, conflicts and notifications. No CLI process
-- is involved — events are fed to the handler directly.

local failed = 0
local function check(cond, name, detail)
  if cond then
    print("OK  " .. name)
  else
    print("FAIL " .. name .. (detail and (": " .. detail) or ""))
    failed = failed + 1
  end
end

local work = assert(os.getenv("STUB_WORK"), "STUB_WORK not set")

local function write_file(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function read_file(path)
  local f = assert(io.open(path, "r"))
  local text = f:read("*a")
  f:close()
  return text
end

-- Collect notifications instead of printing them.
local notes = {}
vim.notify = function(msg, level)
  table.insert(notes, { msg = msg, level = level })
end
local function noted(pattern)
  for _, n in ipairs(notes) do
    if tostring(n.msg):find(pattern) then
      return true
    end
  end
  return false
end

local gdoc = require("gdoc-sync")
local buffers = require("gdoc-sync.buffer")
gdoc.setup({})

---------------------------------------------------------------------------
-- buffer.reload: the rule that stops edits being destroyed
---------------------------------------------------------------------------

local a = work .. "/reload.md"
write_file(a, "line one\n")
vim.cmd("edit " .. a)

-- Clean buffer + changed file → reload.
write_file(a, "line one\nline two from the doc\n")
local result = buffers.reload(a)
check(result == "reloaded" or result == "unchanged", "clean buffer reloads", result)
check(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("from the doc"),
  "reloaded buffer shows the merged file")

-- Modified buffer + changed file → refuse, and say so.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "my unsaved edit" })
check(vim.bo.modified, "buffer is modified for the next check")
write_file(a, "line one\nsomething else entirely\n")
notes = {}
result = buffers.reload(a)
check(result == "modified", "modified buffer is NOT reloaded", tostring(result))
check(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "my unsaved edit",
  "unsaved edit survives")
check(noted("unsaved changes"), "user is told why it was not reloaded")

-- Cursor position survives a reload.
vim.cmd("edit! " .. a)
write_file(a, "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n")
vim.cmd("edit!")
vim.api.nvim_win_set_cursor(0, { 7, 0 })
write_file(a, "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n")
buffers.reload(a)
check(vim.api.nvim_win_get_cursor(0)[1] == 7, "cursor position preserved across reload",
  tostring(vim.api.nvim_win_get_cursor(0)[1]))

-- reload of an unopened file is a no-op, not an error.
check(buffers.reload(work .. "/never-opened.md") == "no-buffer", "unopened file is a no-op")

---------------------------------------------------------------------------
-- write_if_dirty
---------------------------------------------------------------------------

local b = work .. "/autowrite.md"
write_file(b, "original\n")
vim.cmd("edit " .. b)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "typed but not saved" })
check(buffers.write_if_dirty(b), "dirty buffer is written")
check(read_file(b):find("typed but not saved"), "auto-write reached the disk")
check(not buffers.write_if_dirty(b), "clean buffer is not rewritten")

-- Scratch buffers are never written.
vim.cmd("enew")
vim.bo.buftype = "nofile"
check(not buffers.write_if_dirty(""), "scratch buffer is not written")

---------------------------------------------------------------------------
-- Watch event handling
---------------------------------------------------------------------------

local c = work .. "/events.md"
write_file(c, "before\n")
vim.cmd("edit " .. c)

-- A merge event with reload=true pulls the new content into the buffer.
write_file(c, "after the merge\n")
notes = {}
gdoc._on_watch_event(vim.json.encode({
  event = "merged", file = c, detail = "merged remote changes into local file",
  reload = true, pushed = false, conflict = false,
}))
check(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "after the merge",
  "merge event reloads the buffer")
check(noted("merged remote changes"), "merge event is reported")

-- A conflict event is recorded and reported at ERROR level.
notes = {}
gdoc._on_watch_event(vim.json.encode({
  event = "conflict", file = c, detail = "both sides changed in the same place",
  reload = true, conflict = true,
}))
check(gdoc._conflicts[c] ~= nil, "conflict is recorded for :Gdoc conflict")
check(noted("both sides changed"), "conflict is reported")
check(noted("Gdoc resolve"), "conflict message says how to resolve it")

-- A later clean event clears the conflict record.
gdoc._on_watch_event(vim.json.encode({
  event = "pushed", file = c, detail = "pushed local changes",
  pushed = true, conflict = false,
}))
check(gdoc._conflicts[c] == nil, "conflict record cleared once resolved")

-- noop events stay silent (notify = "changes" default).
notes = {}
gdoc._on_watch_event(vim.json.encode({
  event = "noop", file = c, detail = "up to date", reload = false, pushed = false,
}))
check(#notes == 0, "quiet ticks produce no notification", vim.inspect(notes))

-- start/stop are internal and never surface.
notes = {}
gdoc._on_watch_event(vim.json.encode({ event = "start", file = ".", detail = "watching" }))
gdoc._on_watch_event(vim.json.encode({ event = "stop", file = ".", detail = "stopped" }))
check(#notes == 0, "start/stop events are not shown")

-- Garbage on the stream is surfaced, not swallowed or crashed on.
notes = {}
local ok = pcall(gdoc._on_watch_event, "not json at all")
check(ok, "non-JSON line does not crash")
check(noted("not json"), "non-JSON line is surfaced")

-- An event whose file has unsaved edits must not clobber them.
write_file(c, "on disk\n")
vim.cmd("edit! " .. c)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved work" })
write_file(c, "merged by the watcher\n")
notes = {}
gdoc._on_watch_event(vim.json.encode({
  event = "merged", file = c, detail = "merged", reload = true,
}))
check(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "unsaved work",
  "watch event never discards unsaved buffer edits")

---------------------------------------------------------------------------
-- Comment markers (issue #2)
---------------------------------------------------------------------------

local d = work .. "/comments.md"
write_file(d, "# Doc\n\nA paragraph worth commenting on.\n")
vim.cmd("edit! " .. d)
vim.api.nvim_win_set_cursor(0, { 3, 0 })

gdoc.comment({ "this", "needs", "a", "citation" })
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
check(lines[4] == "{>>comment: this needs a citation<<}",
  "comment marker inserted below the cursor", vim.inspect(lines))

gdoc.resolvecomment()
check(vim.api.nvim_buf_get_lines(0, 0, -1, false)[5] == "{>>resolve<<}",
  "resolve marker inserted")

gdoc.reply({ "agreed" })
check(vim.api.nvim_buf_get_lines(0, 0, -1, false)[6] == "{>>reply: agreed<<}",
  "reply marker inserted")

-- :Gdoc comments collects them into the quickfix list.
gdoc.comments()
local qf = vim.fn.getqflist()
check(#qf == 3, "quickfix lists every comment marker", tostring(#qf))
check(qf[1].text:find("comment: this needs"), "quickfix text is the marker body")

---------------------------------------------------------------------------
-- Config surface
---------------------------------------------------------------------------

local cfg = require("gdoc-sync.config")
cfg.setup({ auto_watch = true, auto_write = false, notify = "errors" })
check(cfg.options.auto_watch == true, "auto_watch is configurable")
check(cfg.options.auto_write == false, "auto_write is configurable")
check(cfg.options.safe_reload == true, "safe_reload defaults on")
check(cfg.options.cmd == "gdoc-sync", "defaults survive a partial setup()")
cfg.setup({})

os.exit(failed == 0 and 0 or 1)
