-- Buffer-side safety for live sync.
--
-- The CLI reconciles files *on disk*. A buffer is a second, invisible copy of
-- the same document, and the gap between them is where edits get lost:
--
--   * Reloading a modified buffer discards whatever was typed into it.
--   * NOT reloading is not safe either — the buffer is now stale, and the next
--     :w silently overwrites the merge the watcher just performed, which the
--     following tick then pushes, erasing the other side's edits remotely.
--
-- So the rules here are: never clobber a modified buffer (`safe_reload`), and
-- keep the buffer written often enough that the gap rarely opens at all
-- (`auto_write`). When it does open anyway, say so loudly rather than picking
-- a side.

local M = {}

local function cfg()
  return require("gdoc-sync.config").options
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "gdoc-sync" })
end

--- Buffer number holding `path`, or nil.
function M.bufnr(path)
  if not path or path == "" then
    return nil
  end
  local target = vim.fn.fnamemodify(path, ":p")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.fn.fnamemodify(name, ":p") == target then
        return buf
      end
    end
  end
  return nil
end

--- True if the buffer for `path` has unsaved changes.
function M.is_modified(path)
  local buf = M.bufnr(path)
  return buf ~= nil and vim.bo[buf].modified
end

--- Reload the buffer showing `path` after the file changed on disk.
---
--- Returns "reloaded", "unchanged", "no-buffer", or "modified" — the last
--- meaning the buffer was left alone because reloading would have destroyed
--- unsaved work. Cursor position is preserved across the reload.
function M.reload(path)
  local buf = M.bufnr(path)
  if not buf then
    return "no-buffer"
  end

  if vim.bo[buf].modified then
    if cfg().safe_reload then
      notify(
        ("%s changed on disk but the buffer has unsaved changes — not reloading.\n"):format(
          vim.fn.fnamemodify(path, ":t"))
          .. "Run :Gdoc conflict to compare, or :w to keep your version.",
        vim.log.levels.WARN)
      return "modified"
    end
  end

  -- Preserve the view in every window showing this buffer.
  local views = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      views[win] = vim.api.nvim_win_call(win, vim.fn.winsaveview)
    end
  end

  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent! checktime")
    -- checktime is a no-op unless 'autoread' is on, so force it when the
    -- buffer is clean and still stale.
    if not vim.bo[buf].modified then
      vim.cmd("silent! edit!")
    end
  end)

  for win, view in pairs(views) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview(view)
      end)
    end
  end

  if vim.api.nvim_buf_get_changedtick(buf) == changedtick then
    return "unchanged"
  end
  return "reloaded"
end

--- Write the buffer for `path` if it is modified and safe to write.
---
--- Guards against writing scratch/readonly buffers and anything without a real
--- file behind it.
function M.write_if_dirty(path)
  local buf = M.bufnr(path)
  if not buf or not vim.bo[buf].modified then
    return false
  end
  if vim.bo[buf].buftype ~= "" or not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    return false
  end
  local ok = pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! noautocmd write")
    end)
  end)
  return ok
end

---------------------------------------------------------------------------
-- Auto-write for watched buffers
---------------------------------------------------------------------------

local autowrite_group = vim.api.nvim_create_augroup("GdocSyncAutoWrite", { clear = true })
local watched = {} -- bufnr -> true

--- Start auto-writing the buffer for `path` while it is being watched.
function M.enable_auto_write(path)
  if not cfg().auto_write then
    return
  end
  local buf = M.bufnr(path)
  if not buf or watched[buf] then
    return
  end
  watched[buf] = true
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI", "InsertLeave", "FocusLost" }, {
    group = autowrite_group,
    buffer = buf,
    desc = "gdoc-sync: keep a watched buffer flushed to disk",
    callback = function()
      if watched[buf] then
        M.write_if_dirty(vim.api.nvim_buf_get_name(buf))
      end
    end,
  })
end

--- Stop auto-writing the buffer for `path`.
function M.disable_auto_write(path)
  local buf = M.bufnr(path)
  if buf then
    watched[buf] = nil
    pcall(vim.api.nvim_clear_autocmds, { group = autowrite_group, buffer = buf })
  end
end

function M.disable_all_auto_write()
  watched = {}
  pcall(vim.api.nvim_clear_autocmds, { group = autowrite_group })
end

---------------------------------------------------------------------------
-- Buffer vs. disk comparison
---------------------------------------------------------------------------

--- Open a diff of the buffer against the file on disk.
---
--- Used when a watch merge landed on disk while the buffer had unsaved edits:
--- neither version is safe to throw away, so both get shown.
function M.diff_against_disk(path)
  local buf = M.bufnr(path)
  if not buf then
    notify("no buffer for " .. path, vim.log.levels.WARN)
    return
  end

  local disk = vim.fn.readfile(path)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("diffthis")
  end)

  vim.cmd("vertical new")
  local scratch = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, disk)
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].filetype = vim.bo[buf].filetype
  vim.api.nvim_buf_set_name(scratch, path .. " [on disk]")
  vim.cmd("diffthis")

  notify("left: your buffer — right: the file on disk (already merged). "
    .. "Copy what you need, then :diffoff and :w")
end

return M
