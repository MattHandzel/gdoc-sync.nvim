-- Linked-file cache, fed by `gdoc-sync status --json`.
--
-- The CLI owns state-file resolution (config override, legacy formats, XDG
-- fallback), so we never parse state.yaml ourselves. The cache makes
-- is_linked()/doc_id() free to call from a statusline.

local M = {}

-- absolute local path -> doc id
M.mappings = {}
M.loaded = false

local refreshing = false

--- Re-read mappings asynchronously. cb() fires when the cache is fresh.
function M.refresh(cb)
  if refreshing then
    return
  end
  refreshing = true
  require("gdoc-sync.cli").run({ "status", "--json" }, function(code, stdout, _)
    refreshing = false
    if code == 0 then
      local ok, data = pcall(vim.json.decode, stdout)
      if ok and type(data) == "table" and type(data.links) == "table" then
        local mappings = {}
        for _, row in ipairs(data.links) do
          mappings[row.file] = row.doc_id
        end
        M.mappings = mappings
        M.loaded = true
      end
    end
    if cb then
      cb()
    end
  end)
end

local function normalize(path)
  return vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
end

--- Doc id linked to a local file, or nil. Reads the cache only.
function M.doc_id(path)
  if not path or path == "" then
    return nil
  end
  return M.mappings[normalize(path)]
end

function M.is_linked(path)
  return M.doc_id(path) ~= nil
end

function M.doc_url(path)
  local id = M.doc_id(path)
  return id and ("https://docs.google.com/document/d/" .. id .. "/edit") or nil
end

return M
