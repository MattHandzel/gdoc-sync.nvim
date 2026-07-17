# 📄 gdoc-sync.nvim

> Sync the markdown buffer you're editing with Google Docs — create, push, pull, diff, share, and live-watch without leaving Neovim. A thin, async wrapper around the [gdoc-sync](https://github.com/MattHandzel/gdoc-sync) CLI.

Write in Neovim, share a real Google Doc, and pull your reviewers' comments back into the buffer as [CriticMarkup](https://github.com/CriticMarkup/CriticMarkup-toolkit). The CLI does the heavy lifting; this plugin makes it a vim motion away.

## ✨ Features

- ⚡ **`:Gdoc create`** — current buffer becomes a styled Google Doc; URL lands on your clipboard
- 🔁 **`:Gdoc push` / `:Gdoc pull`** — async, with drift protection: if someone edited the doc since your last pull, you're asked before overwriting (and pull reloads the buffer safely)
- 👀 **`:Gdoc watch`** — live sync in the background: remote edits auto-pull into the buffer, local saves auto-push
- 📊 **`:Gdoc diff`** — unified diff of buffer vs. remote in a split
- 💬 comment round-trip — reviewers' comments arrive as `{>>...<<}` markers on pull; write `{>>reply: thanks!<<}` or `{>>resolve<<}` and push
- 🩺 **`:checkhealth gdoc-sync`** + **`:Gdoc doctor`** — one-glance setup diagnostics
- 📎 statusline component showing when a buffer is linked to a doc

## ⚡ Requirements

- Neovim ≥ 0.9
- The [gdoc-sync CLI](https://github.com/MattHandzel/gdoc-sync) ≥ 0.5 on your `$PATH`, authenticated (`gdoc-sync auth` — one-time [OAuth setup](https://github.com/MattHandzel/gdoc-sync/blob/main/docs/oauth-setup.md))

## 📦 Installation

```lua
-- lazy.nvim
{
  "MattHandzel/gdoc-sync.nvim",
  ft = "markdown",
  config = function()
    require("gdoc-sync").setup()
  end,
}
```

## 🚀 Quick start

```
:Gdoc create              " current buffer → new Google Doc, URL on clipboard
:Gdoc push                " send local edits to the doc
:Gdoc pull                " bring doc edits (and comments) into the buffer
:Gdoc status --remote     " which linked files drifted?
:Gdoc watch               " live sync this file until :Gdoc watch stop
```

## 📖 Commands

All commands operate on the current buffer's file.

| Command | What it does |
|---|---|
| `:Gdoc create [flags]` | Create a doc from the buffer (`--private`, `--view`, `--edit`, `--open`, `--title T`) |
| `:Gdoc push` | Push; on remote drift you're prompted before overwriting |
| `:Gdoc pull` | Pull doc → file, reload buffer (guards unsaved changes) |
| `:Gdoc status [--remote]` | All linked files in a float; `--remote` checks drift |
| `:Gdoc diff` | Unified diff local ↔ remote in a split (`q` closes) |
| `:Gdoc open` | Open the linked doc in your browser |
| `:Gdoc share view\|comment\|edit\|private\|email[:role]` | Change sharing |
| `:Gdoc export [pdf\|docx\|odt\|txt\|html\|epub]` | Export via Drive |
| `:Gdoc link <url>` / `:Gdoc unlink` | Manage the file ↔ doc mapping |
| `:Gdoc watch [all\|stop]` | Background live sync with notifications |
| `:Gdoc doctor` | Full CLI diagnostics in a float |

## ⚙️ Configuration

Defaults shown; everything is optional.

```lua
require("gdoc-sync").setup({
  cmd = "gdoc-sync",          -- CLI executable
  config_file = nil,          -- passed as --config (nil = CLI's own resolution)
  create_args = {},           -- extra flags for every create, e.g. { "--private" }
  open_after_create = false,  -- pop the browser after :Gdoc create
  statusline_icon = "󰈙 gdoc",
  watch_interval = 30,        -- seconds between :Gdoc watch polls
})
```

### Statusline

```lua
-- lualine
sections = { lualine_x = { require("gdoc-sync.statusline").component } }

-- plain 'statusline'
vim.o.statusline = "%f %{%v:lua.require'gdoc-sync.statusline'.component()%}"
```

Shows the icon when the buffer is linked, ` (watching)` while live sync runs, and nothing otherwise. Reads a cache — never blocks.

## 🧪 Tests

```sh
tests/run.sh          # module load + functional tests against a stub CLI (offline)
tests/e2e/real-api.sh # optional: full round-trip against the real Google API
```

The E2E script uses an isolated state file (your real mappings are untouched), creates a private test doc, pushes, pulls, diffs, unlinks, and trashes the doc afterward. It needs an authenticated CLI.

## License

MIT
