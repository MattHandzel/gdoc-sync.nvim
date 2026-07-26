# 📄 gdoc-sync.nvim

> Sync the markdown buffer you're editing with Google Docs — create, push, pull, diff, share, and live-watch without leaving Neovim. A thin, async wrapper around the [gdoc-sync](https://github.com/MattHandzel/gdoc-sync) CLI.

Write in Neovim, share a real Google Doc, and pull your reviewers' comments back into the buffer as [CriticMarkup](https://github.com/CriticMarkup/CriticMarkup-toolkit). The CLI does the heavy lifting; this plugin makes it a vim motion away.

## ✨ Features

- ⚡ **`:Gdoc create`** — current buffer becomes a styled Google Doc; URL lands on your clipboard
- 🔁 **`:Gdoc push` / `:Gdoc pull`** — async, with drift protection: if someone edited the doc since your last pull, you're asked before overwriting (and pull reloads the buffer safely)
- 🔀 **`:Gdoc watch` / `:Gdoc sync`** — live **two-way** sync: edits made in Google Docs and edits made here are merged, not fought over. Unmergeable overlaps become visible conflicts, never silent overwrites
- 🛟 **never loses work** — a buffer with unsaved changes is never reloaded out from under you, every write is backed up, and `:Gdoc restore` brings any version back
- 📊 **`:Gdoc diff`** — unified diff of buffer vs. remote in a split
- 💬 comment round-trip — reviewers' comments arrive as `{>>...<<}` markers on pull; `:Gdoc comment`/`reply`/`resolvecomment` write them back
- 🩺 **`:checkhealth gdoc-sync`** + **`:Gdoc doctor`** — one-glance setup diagnostics
- 📎 statusline component showing when a buffer is linked to a doc

## ⚡ Requirements

- Neovim ≥ 0.9
- The [gdoc-sync CLI](https://github.com/MattHandzel/gdoc-sync) ≥ 0.6 on your `$PATH`, authenticated (`gdoc-sync auth` — one-time [OAuth setup](https://github.com/MattHandzel/gdoc-sync/blob/main/docs/oauth-setup.md))

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
:Gdoc watch               " live two-way sync until :Gdoc watch stop
```

Editing the same document in Google Docs and in Neovim at once is the normal
case, not an accident — `:Gdoc watch` merges both sides. See
[Live two-way sync](#-live-two-way-sync).

## 📖 Commands

All commands operate on the current buffer's file.

| Command | What it does |
|---|---|
| `:Gdoc create [flags]` | Create a doc from the buffer (`--private`, `--view`, `--edit`, `--open`, `--title T`) |
| `:Gdoc push` | Push; on remote drift you're prompted before overwriting |
| `:Gdoc pull` | Pull doc → file, reload buffer (guards unsaved changes) |
| `:Gdoc sync [--adopt-local\|--adopt-remote]` | One safe two-way merge |
| `:Gdoc watch [all\|stop\|status]` | Background live two-way sync |
| `:Gdoc conflict` | Review the current conflict (markers, or buffer ↔ disk diff) |
| `:Gdoc resolve` | Clear the conflict flag and resume syncing |
| `:Gdoc restore [N]` | List automatic backups, or restore the Nth |
| `:Gdoc status [--remote]` | All linked files in a float; `--remote` checks drift |
| `:Gdoc diff` | Unified diff local ↔ remote in a split (`q` closes) |
| `:Gdoc open` | Open the linked doc in your browser |
| `:Gdoc share view\|comment\|edit\|private\|email[:role]` | Change sharing |
| `:Gdoc export [pdf\|docx\|odt\|txt\|html\|epub]` | Export via Drive |
| `:Gdoc comment [text]` | Queue a new comment on the doc at the cursor |
| `:Gdoc reply [text]` | Reply to the pulled comment above the cursor |
| `:Gdoc resolvecomment` | Resolve the pulled comment above the cursor |
| `:Gdoc comments` | Every comment in the buffer, in the quickfix list |
| `:Gdoc link <url>` / `:Gdoc unlink` | Manage the file ↔ doc mapping |
| `:Gdoc doctor` | Full CLI diagnostics in a float |

## 🔀 Live two-way sync

`:Gdoc watch` reconciles the buffer's file with its doc on a timer. Edits made
in Google Docs and edits made in Neovim are **merged**, not fought over — see
[the CLI's two-way sync model](https://github.com/MattHandzel/gdoc-sync#two-way-sync)
for how that works. The plugin adds the editor half of the safety:

- **A modified buffer is never reloaded.** If the watcher merges remote changes
  into a file whose buffer has unsaved edits, you get told rather than
  overwritten; `:Gdoc conflict` diffs your buffer against what's on disk.
- **Watched buffers are auto-written** (on `CursorHold`, `InsertLeave`,
  `FocusLost`). The watcher reconciles the file *on disk*, so edits sitting
  unsaved in a buffer are invisible to it — flushing them keeps the two from
  drifting apart. Set `auto_write = false` to opt out.
- **Conflicts are visible**: git-style markers land in the file, `:Gdoc
  conflict` jumps to the first one, and `:Gdoc resolve` resumes syncing.
- Watchers stop when their buffer closes and when Neovim exits.

To have linked buffers start syncing on their own, set `auto_watch`:

```lua
require("gdoc-sync").setup({
  auto_watch = true,     -- or "prompt" to be asked the first time per file
})
```

## ⚙️ Configuration

Defaults shown; everything is optional.

```lua
require("gdoc-sync").setup({
  cmd = "gdoc-sync",          -- CLI executable
  config_file = nil,          -- passed as --config (nil = CLI's own resolution)
  create_args = {},           -- extra flags for every create, e.g. { "--private" }
  open_after_create = false,  -- pop the browser after :Gdoc create
  clipboard = nil,            -- nil = CLI's `clipboard:` setting; false = --no-copy
  statusline_icon = "󰈙 gdoc",

  -- Live sync
  watch_interval = 15,        -- seconds between polls (nil = CLI's setting)
  auto_watch = false,         -- true | "prompt" | false — watch linked buffers
  auto_write = true,          -- flush watched buffers so the watcher sees edits
  safe_reload = true,         -- never reload a buffer with unsaved changes
  notify = "changes",         -- "all" | "changes" | "errors"
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
