-- Async wrapper around the gdoc-sync CLI.
--
-- Every command goes through run(): builds argv from config, runs the CLI
-- without blocking the editor, and delivers (code, stdout, stderr) to the
-- callback on the main loop. vim.system on 0.10+, jobstart on 0.9.

local M = {}

local function argv(args)
  local cfg = require("gdoc-sync.config").options
  local cmd = { cfg.cmd }
  if cfg.config_file then
    vim.list_extend(cmd, { "--config", cfg.config_file })
  end
  vim.list_extend(cmd, args)
  return cmd
end

--- Run the CLI asynchronously. cb(code, stdout, stderr) on the main loop.
function M.run(args, cb)
  local cmd = argv(args)
  if vim.fn.executable(cmd[1]) ~= 1 then
    vim.schedule(function()
      cb(127, "", ("gdoc-sync.nvim: %q is not executable — install the CLI "
        .. "from https://github.com/MattHandzel/gdoc-sync"):format(cmd[1]))
    end)
    return
  end

  if vim.system then
    vim.system(cmd, { text = true }, function(res)
      vim.schedule(function()
        cb(res.code, res.stdout or "", res.stderr or "")
      end)
    end)
    return
  end

  -- Neovim 0.9 fallback.
  local out, err = {}, {}
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      out = data
    end,
    on_stderr = function(_, data)
      err = data
    end,
    on_exit = function(_, code)
      cb(code, table.concat(out, "\n"), table.concat(err, "\n"))
    end,
  })
end

--- Start a long-running CLI process, streaming stdout/stderr lines to
--- on_line(line). Returns a handle with :stop().
function M.stream(args, on_line, on_exit)
  local cmd = argv(args)
  local job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          vim.schedule(function()
            on_line(line)
          end)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          vim.schedule(function()
            on_line(line)
          end)
        end
      end
    end,
    on_exit = function(_, code)
      if on_exit then
        vim.schedule(function()
          on_exit(code)
        end)
      end
    end,
  })
  return {
    job = job,
    stop = function()
      pcall(vim.fn.jobstop, job)
    end,
  }
end

return M
