-- Every module loads; :Gdoc is registered; setup() runs clean.
local failed = 0
local mods = {
  "gdoc-sync", "gdoc-sync.config", "gdoc-sync.cli", "gdoc-sync.links",
  "gdoc-sync.commands", "gdoc-sync.statusline", "gdoc-sync.health",
}
for _, m in ipairs(mods) do
  local ok, err = pcall(require, m)
  if ok then
    print("OK  require " .. m)
  else
    print("FAIL require " .. m .. ": " .. tostring(err))
    failed = failed + 1
  end
end

if vim.fn.exists(":Gdoc") == 2 then
  print("OK  :Gdoc registered")
else
  print("FAIL :Gdoc not registered")
  failed = failed + 1
end

local ok, err = pcall(require("gdoc-sync").setup, { statusline_icon = "X" })
if ok and require("gdoc-sync.config").options.statusline_icon == "X" then
  print("OK  setup() merges options")
else
  print("FAIL setup(): " .. tostring(err))
  failed = failed + 1
end

-- Completion offers subcommands.
local comp = require("gdoc-sync.commands").complete("p", "Gdoc p", 6)
if vim.tbl_contains(comp, "push") and vim.tbl_contains(comp, "pull") then
  print("OK  subcommand completion")
else
  print("FAIL subcommand completion: " .. vim.inspect(comp))
  failed = failed + 1
end

os.exit(failed == 0 and 0 or 1)
