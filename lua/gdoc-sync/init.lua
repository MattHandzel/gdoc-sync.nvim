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

--- Reload the current buffer from disk (after a pull rewrote the file).
local function reload_buffer()
  vim.cmd("silent! checktime")
  if not vim.bo.modified then
    vim.cmd("silent! edit!")
  end
end

local function first_doc_url(text)
  return text:match("https://docs%.google%.com/document/d/[%w_%-]+[%w/=?_%-]*")
end

function M.setup(opts)
  require("gdoc-sync.config").setup(opts)
  -- Warm the linked-file cache so the statusline is accurate soon after
  -- startup; a plain (non --remote) status never touches the network.
  vim.defer_fn(function()
    links().refresh()
  end, 100)
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
    cli().run({ "pull", file }, function(code, _, stderr)
      if code ~= 0 then
        notify("pull failed:\n" .. stderr, vim.log.levels.ERROR)
        return
      end
      reload_buffer()
      notify("pulled " .. vim.fn.fnamemodify(file, ":t"))
      links().refresh()
    end)
  end
  if vim.bo.modified then
    vim.ui.select({ "Discard buffer changes and pull", "Cancel" }, {
      prompt = "Buffer has unsaved changes; pull overwrites the file on disk.",
    }, function(choice)
      if choice == "Discard buffer changes and pull" then
        vim.cmd("silent! edit!")
        do_pull()
      end
    end)
  else
    do_pull()
  end
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

--- :Gdoc watch        — watch the current file
--- :Gdoc watch all    — watch every linked file
--- :Gdoc watch stop   — stop all watchers
function M.watch(args)
  local sub = args and args[1]
  if sub == "stop" then
    local n = 0
    for _, w in pairs(M._watchers) do
      w.stop()
      n = n + 1
    end
    M._watchers = {}
    notify(n > 0 and ("stopped " .. n .. " watcher(s)") or "no watchers running")
    return
  end

  local cfg = require("gdoc-sync.config").options
  local cmd = { "watch", "--interval", tostring(cfg.watch_interval) }
  local key
  if sub == "all" then
    table.insert(cmd, "--all")
    key = "*"
  else
    local file = buf_file()
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

  M._watchers[key] = cli().stream(cmd, function(line)
    -- Auto-pull rewrites files on disk; pick the changes up immediately.
    vim.cmd("silent! checktime")
    notify(line)
  end, function(code)
    M._watchers[key] = nil
    if code ~= 0 then
      notify("watch exited with code " .. code, vim.log.levels.WARN)
    end
  end)
  notify("watching " .. key .. " (every " .. cfg.watch_interval .. "s) — :Gdoc watch stop to end")
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
