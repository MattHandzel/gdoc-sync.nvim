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
  -- Statusline text for a linked buffer (see :h gdoc-sync-statusline).
  statusline_icon = "󰈙 gdoc",
  -- Seconds between polls for :Gdoc watch.
  watch_interval = 30,
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
