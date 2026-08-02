-- gdoc-sync.nvim — sync the current markdown buffer with Google Docs.
-- Public API; :Gdoc dispatches here (see lua/gdoc-sync/commands.lua).

local M = {}

local function cli()
  return require("gdoc-sync.cli")
end

local function links()
  return require("gdoc-sync.links")
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "gdoc-sync" })
end

--- Absolute path of the current buffer's file, or nil (with a warning).
local function buf_file()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    notify("current buffer has no file — save it first", vim.log.levels.WARN)
    return nil
  end
  return vim.fn.fnamemodify(name, ":p")
end

--- Write the buffer if it has unsaved changes, so the CLI sees them.
local function save_buffer()
  if vim.bo.modified then
    vim.cmd.update()
  end
end

local function first_doc_url(text)
  return text:match("https://docs%.google%.com/document/d/[%w_%-]+[%w/=?_%-]*")
end

function M.setup(opts)
  local cfg = require("gdoc-sync.config").setup(opts)
  -- Claim the flag :Gdoc uses to decide whether the plugin still needs
  -- initialising. Without this, the first :Gdoc command would call setup({})
  -- and silently replace everything configured here with the defaults — so a
  -- configured `cmd` would fall back to whatever `gdoc-sync` is on $PATH, and
  -- auto_watch/watch_interval/notify would never take effect.
  vim.g._gdoc_sync_setup_done = 1
  -- Warm the linked-file cache so the statusline is accurate soon after
  -- startup; a plain (non --remote) status never touches the network.
  vim.defer_fn(function()
    links().refresh()
    if cfg.auto_watch then
      M._setup_auto_watch()
    end
  end, 100)
end

---------------------------------------------------------------------------
-- Auto-watch (issue #3): keep linked buffers live-syncing while nvim runs
---------------------------------------------------------------------------

local auto_group = nil
M._auto_watch_declined = {}

--- Start watching a linked buffer, honouring the auto_watch mode.
local function maybe_auto_watch(bufnr)
  local cfg = require("gdoc-sync.config").options
  if not cfg.auto_watch then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or vim.bo[bufnr].buftype ~= "" then
    return
  end
  local file = vim.fn.fnamemodify(name, ":p")
  if M._watchers[file] or M._watchers["*"] or M._auto_watch_declined[file] then
    return
  end
  -- Only linked files can be watched at all; the cache answers without a
  -- network round trip.
  if not links().is_linked(file) then
    return
  end

  local function start()
    -- The buffer may have changed since the cache refresh completed.
    if vim.api.nvim_buf_is_valid(bufnr) and not M._watchers[file] then
      vim.api.nvim_buf_call(bufnr, function()
        M.watch({})
      end)
    end
  end

  if cfg.auto_watch == "prompt" then
    vim.ui.select({ "Watch this file", "Not now" }, {
      prompt = ("Live-sync %s with its Google Doc?"):format(
        vim.fn.fnamemodify(file, ":t")),
    }, function(choice)
      if choice == "Watch this file" then
        start()
      else
        M._auto_watch_declined[file] = true
      end
    end)
  else
    start()
  end
end

function M._setup_auto_watch()
  if auto_group then
    return
  end
  auto_group = vim.api.nvim_create_augroup("GdocSyncAutoWatch", { clear = true })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
    group = auto_group,
    pattern = { "*.md", "*.markdown" },
    desc = "gdoc-sync: auto-watch linked markdown buffers",
    callback = function(ev)
      -- The link cache may still be cold on the very first buffer.
      if links().loaded then
        maybe_auto_watch(ev.buf)
      else
        links().refresh(function()
          maybe_auto_watch(ev.buf)
        end)
      end
    end,
  })

  -- A watcher for a file nobody is looking at is just API quota.
  vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
    group = auto_group,
    pattern = { "*.md", "*.markdown" },
    desc = "gdoc-sync: stop watching a closed buffer",
    callback = function(ev)
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if name ~= "" then
        M.watch_stop_file(vim.fn.fnamemodify(name, ":p"))
      end
    end,
  })

  -- Leaving a watcher behind would orphan the process.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = auto_group,
    desc = "gdoc-sync: stop watchers on exit",
    callback = function()
      for _, w in pairs(M._watchers) do
        pcall(w.stop)
      end
      M._watchers = {}
    end,
  })

  -- Catch the buffer that was already open when setup() ran.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "markdown" then
      maybe_auto_watch(buf)
    end
  end
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

function M.create(args)
  local file = buf_file()
  if not file then
    return
  end
  save_buffer()
  local cfg = require("gdoc-sync.config").options
  local cmd = { "create" }
  vim.list_extend(cmd, cfg.create_args)
  -- nil defers to the CLI's own `clipboard:` setting; only an explicit false
  -- suppresses the copy from here.
  if cfg.clipboard == false then
    table.insert(cmd, "--no-copy")
  end
  vim.list_extend(cmd, args or {})
  table.insert(cmd, file)
  notify("creating doc…")
  cli().run(cmd, function(code, stdout, stderr)
    if code ~= 0 then
      notify("create failed:\n" .. stderr, vim.log.levels.ERROR)
      return
    end
    links().refresh()
    local url = first_doc_url(stdout)
    local suffix = stdout:find("Copied to clipboard", 1, true) and "\n(URL on clipboard)" or ""
    notify("created " .. (url or "doc") .. suffix)
    if cfg.open_after_create and url then
      M.open()
    end
  end)
end

--- Push; on drift (exit 2) ask before overwriting the remote.
function M.push(args)
  local file = buf_file()
  if not file then
    return
  end
  save_buffer()
  local cmd = { "push" }
  vim.list_extend(cmd, args or {})
  table.insert(cmd, file)
  cli().run(cmd, function(code, _, stderr)
    if code == 0 then
      notify("pushed " .. vim.fn.fnamemodify(file, ":t"))
      links().refresh()
      return
    end
    if code == 2 and stderr:find("--yes", 1, true) then
      vim.ui.select({ "Overwrite remote", "Cancel" }, {
        prompt = "Google Doc changed since your last pull — overwrite it?",
      }, function(choice)
        if choice ~= "Overwrite remote" then
          notify("push cancelled")
          return
        end
        local retry = { "push", "--yes" }
        vim.list_extend(retry, args or {})
        table.insert(retry, file)
        cli().run(retry, function(code2, _, stderr2)
          if code2 == 0 then
            notify("pushed " .. vim.fn.fnamemodify(file, ":t") .. " (overwrote remote)")
            links().refresh()
          else
            notify("push failed:\n" .. stderr2, vim.log.levels.ERROR)
          end
        end)
      end)
      return
    end
    notify("push failed:\n" .. stderr, vim.log.levels.ERROR)
  end)
end

function M.pull()
  local file = buf_file()
  if not file then
    return
  end
  local function do_pull()
    cli().run({ "pull", file }, function(code, stdout, stderr)
      if code ~= 0 then
        notify("pull failed:\n" .. stderr, vim.log.levels.ERROR)
        return
      end
      require("gdoc-sync.buffer").reload(file)
      notify("pulled " .. vim.fn.fnamemodify(file, ":t")
        .. " (previous version backed up — :Gdoc restore)")
      -- A successful pull can still be lossy: the Docs API cannot report what
      -- an equation contains, so one the CLI could not match arrives as an
      -- `[equation]` marker. It says so on stdout, which is otherwise
      -- discarded — and a warning nobody sees is the same as no warning.
      for line in (stdout or ""):gmatch("[^\n]+") do
        if line:match("WARNING") then
          notify(vim.trim(line), vim.log.levels.WARN)
        end
      end
      links().refresh()
    end)
  end
  if vim.bo.modified then
    vim.ui.select({ "Merge instead (:Gdoc sync)", "Discard buffer changes and pull", "Cancel" }, {
      prompt = "Buffer has unsaved changes; a pull overwrites the file on disk.",
    }, function(choice)
      if choice == "Discard buffer changes and pull" then
        vim.cmd("silent! edit!")
        do_pull()
      elseif choice == "Merge instead (:Gdoc sync)" then
        M.sync({})
      end
    end)
  else
    do_pull()
  end
end

---------------------------------------------------------------------------
-- Comments (issue #2): work with the doc's comment threads from markdown
---------------------------------------------------------------------------

--- CriticMarkup patterns the CLI round-trips.
local COMMENT_PATTERN = "{>>.-<<}"

--- Insert a CriticMarkup marker on the line below the cursor.
local function insert_marker(text)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, { text })
  vim.api.nvim_win_set_cursor(0, { row + 1, #text })
end

--- :Gdoc comment <text> — add a new comment on the doc, anchored by context.
---
--- Written as {>>comment: ...<<}; the next push creates it on the doc and
--- strips the marker from what gets uploaded.
function M.comment(args)
  local text = table.concat(args or {}, " ")
  if text == "" then
    vim.ui.input({ prompt = "Comment: " }, function(input)
      if input and input ~= "" then
        insert_marker("{>>comment: " .. input .. "<<}")
        notify("comment queued — :Gdoc push to send it")
      end
    end)
    return
  end
  insert_marker("{>>comment: " .. text .. "<<}")
  notify("comment queued — :Gdoc push to send it")
end

--- :Gdoc reply <text> — reply to the pulled comment above the cursor.
function M.reply(args)
  local text = table.concat(args or {}, " ")
  local function place(reply)
    insert_marker("{>>reply: " .. reply .. "<<}")
    notify("reply queued — :Gdoc push to send it")
  end
  if text == "" then
    vim.ui.input({ prompt = "Reply: " }, function(input)
      if input and input ~= "" then
        place(input)
      end
    end)
    return
  end
  place(text)
end

--- :Gdoc resolvecomment — resolve the pulled comment above the cursor.
function M.resolvecomment()
  insert_marker("{>>resolve<<}")
  notify("resolve queued — :Gdoc push to apply it")
end

--- :Gdoc comments — list every comment marker in the buffer in the quickfix list.
function M.comments()
  local file = buf_file()
  if not file then
    return
  end
  local items = {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    for match in line:gmatch(COMMENT_PATTERN) do
      table.insert(items, {
        filename = file,
        lnum = lnum,
        col = (line:find(match, 1, true) or 1),
        text = match:sub(4, -4),
      })
    end
  end
  if #items == 0 then
    notify("no comments in this buffer — :Gdoc pull to fetch the doc's comments")
    return
  end
  vim.fn.setqflist({}, " ", { title = "gdoc-sync comments", items = items })
  vim.cmd("copen")
end

--- Full `status` report in a float. Pass "--remote" to check for drift.
function M.status(args)
  local cmd = { "status" }
  vim.list_extend(cmd, args or {})
  cli().run(cmd, function(code, stdout, stderr)
    if code ~= 0 then
      notify("status failed:\n" .. stderr, vim.log.levels.ERROR)
      return
    end
    M._float(stdout, "gdoc-sync status")
  end)
end

--- Unified diff (local vs remote) in a split. Exit 1 = differences.
function M.diff()
  local file = buf_file()
  if not file then
    return
  end
  save_buffer()
  cli().run({ "diff", file }, function(code, stdout, stderr)
    if code == 0 then
      notify("no differences")
    elseif code == 1 and stdout ~= "" then
      vim.cmd("botright new")
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(stdout, "\n"))
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].modifiable = false
      vim.bo[buf].filetype = "diff"
      vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
    else
      notify("diff failed:\n" .. stderr, vim.log.levels.ERROR)
    end
  end)
end

function M.open()
  local file = buf_file()
  if not file then
    return
  end
  cli().run({ "open", file }, function(code, stdout, stderr)
    if code ~= 0 then
      notify("open failed:\n" .. stderr, vim.log.levels.ERROR)
    else
      notify("opened " .. vim.trim(stdout))
    end
  end)
end

--- :Gdoc share view|comment|edit|private|email[:role] …
function M.share(args)
  local file = buf_file()
  if not file then
    return
  end
  local cmd = { "share", file }
  for _, a in ipairs(args or {}) do
    if a == "view" or a == "comment" or a == "edit" then
      vim.list_extend(cmd, { "--anyone", a })
    elseif a == "private" then
      table.insert(cmd, "--private")
    elseif a:find("@", 1, true) then
      vim.list_extend(cmd, { "--with", a })
    else
      table.insert(cmd, a) -- raw CLI flag pass-through
    end
  end
  cli().run(cmd, function(code, stdout, stderr)
    if code ~= 0 then
      notify("share failed:\n" .. stderr, vim.log.levels.ERROR)
    else
      notify(vim.trim(stdout))
    end
  end)
end

--- :Gdoc export [pdf|docx|odt|txt|html|epub]
function M.export(args)
  local file = buf_file()
  if not file then
    return
  end
  local cmd = { "export" }
  local fmt = args and args[1]
  if fmt then
    vim.list_extend(cmd, { "--format", fmt })
  end
  table.insert(cmd, file)
  notify("exporting…")
  cli().run(cmd, function(code, stdout, stderr)
    if code ~= 0 then
      notify("export failed:\n" .. stderr, vim.log.levels.ERROR)
    else
      notify(vim.trim(stdout))
    end
  end)
end

function M.link(args)
  local file = buf_file()
  if not file then
    return
  end
  local url = args and args[1]
  if not url then
    notify("usage: :Gdoc link <doc-url-or-id>", vim.log.levels.WARN)
    return
  end
  cli().run({ "link", file, url }, function(code, stdout, stderr)
    if code ~= 0 then
      notify("link failed:\n" .. stderr, vim.log.levels.ERROR)
    else
      notify(vim.trim(stdout))
      links().refresh()
    end
  end)
end

function M.unlink()
  local file = buf_file()
  if not file then
    return
  end
  cli().run({ "unlink", file }, function(code, stdout, stderr)
    if code ~= 0 then
      notify("unlink failed:\n" .. stderr, vim.log.levels.ERROR)
    else
      notify(vim.trim(stdout))
      links().refresh()
    end
  end)
end

---------------------------------------------------------------------------
-- Watch (live sync)
---------------------------------------------------------------------------

M._watchers = {}

--- Files currently flagged as conflicted by the CLI, for :Gdoc conflict.
M._conflicts = {}

local function buffers()
  return require("gdoc-sync.buffer")
end

--- Should a watch event at this severity be shown?
local function should_notify(event, changed)
  local level = require("gdoc-sync.config").options.notify
  if level == "all" then
    return true
  end
  if level == "errors" then
    return event == "conflict" or event == "error"
  end
  return changed or event == "conflict" or event == "error"
end

--- Handle one `gdoc-sync watch --json` event.
---
--- The CLI reports whether the file on disk actually changed and whether a
--- conflict was raised, so the plugin can reload exactly when it should
--- instead of guessing from log prose.
function M._on_watch_event(line)
  local ok, ev = pcall(vim.json.decode, line)
  if not ok or type(ev) ~= "table" or not ev.event then
    -- Not an event (a warning on stderr, say) — surface it as-is.
    if line ~= "" then
      notify(line, vim.log.levels.WARN)
    end
    return
  end

  if ev.event == "start" or ev.event == "stop" then
    return
  end

  local name = ev.file and vim.fn.fnamemodify(ev.file, ":t") or "?"

  if ev.conflict then
    M._conflicts[ev.file] = ev.detail
  else
    M._conflicts[ev.file] = nil
  end

  -- The file on disk moved; bring the buffer along if that is safe.
  if ev.reload and ev.file then
    local result = buffers().reload(ev.file)
    if result == "modified" then
      -- reload() already explained the situation; don't double-notify.
      return
    end
  end

  if not should_notify(ev.event, ev.reload or ev.pushed) then
    return
  end

  local level = vim.log.levels.INFO
  if ev.event == "conflict" then
    level = vim.log.levels.ERROR
  elseif ev.event == "error" then
    level = vim.log.levels.WARN
  end

  local msg = name .. ": " .. (ev.detail or ev.event)
  if ev.event == "conflict" then
    msg = msg .. "\n:Gdoc conflict to review, :Gdoc resolve when done."
  end
  notify(msg, level)
end

--- :Gdoc watch        — watch the current file
--- :Gdoc watch all    — watch every linked file
--- :Gdoc watch stop   — stop all watchers
--- :Gdoc watch status — list running watchers
function M.watch(args)
  local sub = args and args[1]
  if sub == "stop" then
    return M.watch_stop()
  end
  if sub == "status" then
    local running = vim.tbl_keys(M._watchers)
    if #running == 0 then
      notify("no watchers running")
    else
      notify("watching:\n  " .. table.concat(running, "\n  "))
    end
    return
  end

  local cfg = require("gdoc-sync.config").options
  local cmd = { "watch", "--json" }
  if cfg.watch_interval then
    vim.list_extend(cmd, { "--interval", tostring(cfg.watch_interval) })
  end

  local key, file
  if sub == "all" then
    table.insert(cmd, "--all")
    key = "*"
  else
    file = buf_file()
    if not file then
      return
    end
    table.insert(cmd, file)
    key = file
  end
  if M._watchers[key] then
    notify("already watching " .. key, vim.log.levels.WARN)
    return
  end

  M._watchers[key] = cli().stream(cmd, M._on_watch_event, function(code)
    M._watchers[key] = nil
    if file then
      buffers().disable_auto_write(file)
    end
    if code ~= 0 then
      notify("watch exited with code " .. code, vim.log.levels.WARN)
    end
  end)

  -- Keep the buffer flushed so the watcher can actually see what was typed.
  if file then
    buffers().enable_auto_write(file)
  end

  local every = cfg.watch_interval and (" every " .. cfg.watch_interval .. "s") or ""
  notify("watching " .. vim.fn.fnamemodify(key, ":t") .. every
    .. " — :Gdoc watch stop to end")
end

--- Stop every running watcher.
function M.watch_stop()
  local n = 0
  for key, w in pairs(M._watchers) do
    w.stop()
    if key ~= "*" then
      buffers().disable_auto_write(key)
    end
    n = n + 1
  end
  M._watchers = {}
  buffers().disable_all_auto_write()
  notify(n > 0 and ("stopped " .. n .. " watcher(s)") or "no watchers running")
end

--- Stop the watcher for one file (used when its buffer goes away).
function M.watch_stop_file(file)
  local w = M._watchers[file]
  if w then
    w.stop()
    M._watchers[file] = nil
    buffers().disable_auto_write(file)
  end
end

---------------------------------------------------------------------------
-- Reconcile / conflicts
---------------------------------------------------------------------------

--- :Gdoc sync [--adopt-local|--adopt-remote] — one safe two-way merge.
function M.sync(args)
  local file = buf_file()
  if not file then
    return
  end
  save_buffer()
  local cmd = { "sync" }
  vim.list_extend(cmd, args or {})
  table.insert(cmd, file)
  notify("syncing…")
  cli().run(cmd, function(code, stdout, stderr)
    -- Exit 2 means "conflicted", which is a result, not a failure.
    if code ~= 0 and code ~= 2 then
      notify("sync failed:\n" .. (stderr ~= "" and stderr or stdout), vim.log.levels.ERROR)
      return
    end
    buffers().reload(file)
    links().refresh()
    if code == 2 then
      M._conflicts[file] = vim.trim(stdout)
      notify(vim.trim(stdout) .. "\n:Gdoc conflict to review.", vim.log.levels.ERROR)
    else
      notify(vim.trim(stdout))
    end
  end)
end

--- :Gdoc resolve — clear the conflict flag once the file is sorted out.
function M.resolve(args)
  local file = buf_file()
  if not file then
    return
  end
  save_buffer()
  local cmd = { "resolve" }
  vim.list_extend(cmd, args or {})
  table.insert(cmd, file)
  cli().run(cmd, function(code, stdout, stderr)
    if code ~= 0 then
      notify("resolve failed:\n" .. (stderr ~= "" and stderr or stdout), vim.log.levels.ERROR)
      return
    end
    M._conflicts[file] = nil
    notify(vim.trim(stdout))
  end)
end

--- :Gdoc conflict — review the current file's conflict.
---
--- Jumps to the first merge marker if the file has them; otherwise diffs the
--- buffer against what is on disk.
function M.conflict()
  local file = buf_file()
  if not file then
    return
  end
  local markers = vim.fn.search("^<<<<<<< ", "cw")
  if markers > 0 then
    notify("jumped to the first merge marker — "
      .. "edit the file until only your text remains, then :Gdoc resolve")
    return
  end
  if buffers().is_modified(file) then
    buffers().diff_against_disk(file)
    return
  end
  local detail = M._conflicts[file]
  if detail then
    M._float(detail, "gdoc-sync conflict")
  else
    notify("no conflict recorded for this file")
  end
end

--- :Gdoc restore [N] — restore the file from an automatic backup.
function M.restore(args)
  local file = buf_file()
  if not file then
    return
  end
  local cmd = { "restore", file }
  local index = args and args[1]
  if index then
    vim.list_extend(cmd, { "--index", tostring(index) })
  end
  cli().run(cmd, function(code, stdout, stderr)
    if code ~= 0 then
      notify("restore failed:\n" .. (stderr ~= "" and stderr or stdout), vim.log.levels.ERROR)
      return
    end
    if index then
      buffers().reload(file)
    end
    M._float(vim.trim(stdout), "gdoc-sync restore")
  end)
end

---------------------------------------------------------------------------
-- Doctor
---------------------------------------------------------------------------

function M.doctor()
  notify("running doctor…")
  cli().run({ "doctor" }, function(_, stdout, stderr)
    local text = stdout
    if stderr ~= "" then
      text = text .. "\n" .. stderr
    end
    M._float(text, "gdoc-sync doctor")
  end)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function M._float(text, title)
  local lines = vim.split(text:gsub("%s+$", ""), "\n")
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(math.max(width + 2, 40), vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 4)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. (title or "gdoc-sync") .. " ",
  })
  vim.keymap.set("n", "q", function()
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, nowait = true })
end

return M
