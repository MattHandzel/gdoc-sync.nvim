-- User configuration. Everything has a working default; setup() is optional.

local M = {}

local defaults = {
  -- The gdoc-sync executable. Absolute path or anything on $PATH.
  cmd = "gdoc-sync",
  -- Passed to the CLI as --config; nil uses the CLI's own resolution
  -- ($GDOC_SYNC_CONFIG, then ~/.config/gdoc-sync/config.yaml).
  config_file = nil,
  -- Extra args appended to every `create` (e.g. { "--private" }).
  create_args = {},
  -- Open the doc in the browser right after :Gdoc create.
  open_after_create = false,
  -- Copy the new doc's URL to the clipboard on :Gdoc create.
  --   nil   — leave it to the CLI's own `clipboard:` config setting
  --   true  — always copy (passes nothing; the CLI default is to copy)
  --   false — never copy (passes --no-copy)
  -- The CLI picks the right tool for the platform (wl-copy, xclip, pbcopy,
  -- clip.exe under WSL, termux-clipboard-set, or an OSC 52 escape over SSH).
  clipboard = nil,
  -- Statusline text for a linked buffer (see :h gdoc-sync-statusline).
  statusline_icon = "󰈙 gdoc",

  ---------------------------------------------------------------------------
  -- Live sync
  ---------------------------------------------------------------------------
  -- Seconds between polls for :Gdoc watch. nil uses the CLI's watch_interval.
  watch_interval = 15,

  -- Start a watcher automatically for linked markdown buffers.
  --   false    — never (use :Gdoc watch by hand)
  --   true     — for every linked buffer you open
  --   "prompt" — ask the first time you open a linked buffer in a session
  auto_watch = false,

  -- Write a watched buffer automatically while you edit it.
  --
  -- This is what makes two-way sync safe rather than merely automatic. The
  -- watcher reconciles the file *on disk*; edits sitting unsaved in a buffer
  -- are invisible to it, so a remote change would be merged into a file that
  -- does not have them — and your next :w would then push over the merge.
  -- Writing on CursorHold keeps disk and buffer close enough together that
  -- the window never opens. Only ever applies to watched, linked buffers.
  auto_write = true,

  -- Never reload a buffer that has unsaved changes, even when the file on
  -- disk moved underneath it. Leave this true: false can discard your edits.
  safe_reload = true,

  -- Notification verbosity for watch events:
  --   "all"     — every sync event
  --   "changes" — only when something actually changed (default)
  --   "errors"  — only conflicts and failures
  notify = "changes",
}

M.options = vim.deepcopy(defaults)
M.defaults = defaults

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return M.options
end

return M
