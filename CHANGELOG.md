# Changelog

## 0.3.0 (2026-08-02)

Pairs with gdoc-sync CLI 0.7, where LaTeX equations stopped being deleted on
pull. The editor half of that is small but load-bearing:

- **A successful pull can still be lossy, and now says so.** The Docs API
  cannot report what an equation contains, so one the CLI could not match
  arrives as an `[equation]` marker. The CLI prints that warning on stdout —
  which `:Gdoc pull` discarded outright, so it reached nobody. Warnings are now
  surfaced as notifications.

## 0.2.0 (2026-07-26)

Requires gdoc-sync CLI >= 0.6 (`:checkhealth gdoc-sync` will tell you).

### Live sync no longer loses edits

The CLI's 0.6 sync engine merges the two sides instead of overwriting one of
them. This release supplies the editor half of that safety, which is where the
remaining ways to lose work lived:

- **A modified buffer is never reloaded.** Previously a `checktime` on every
  watch event could pull a rewritten file into the buffer. Now, if the watcher
  merges remote changes into a file whose buffer has unsaved edits, the buffer
  is left alone and you are told — `:Gdoc conflict` diffs buffer against disk
  so you can keep both. `safe_reload = false` opts out.
- **Watched buffers are auto-written** on `CursorHold`, `InsertLeave` and
  `FocusLost`. The CLI reconciles the file on disk, so unsaved buffer edits
  were invisible to it: a remote change got merged into a file lacking them,
  and the next `:w` clobbered the merge, which the following tick pushed —
  erasing the other side remotely. `auto_write = false` opts out.
- Watch events are read from `watch --json` rather than scraped from log
  prose, so the plugin reloads exactly when the file changed and knows when a
  conflict was raised. Quiet ticks no longer notify at all (`notify` setting).
- Cursor position and window view survive a reload.

### New

- `:Gdoc sync [--adopt-local|--adopt-remote|--no-push|--force]` — one safe
  two-way merge.
- `:Gdoc conflict` — jump to the first merge marker, or diff buffer ↔ disk.
- `:Gdoc resolve` — clear the conflict flag and resume syncing.
- `:Gdoc restore [N]` — list or restore the CLI's automatic backups.
- `:Gdoc watch status` — list running watchers; watchers now stop when their
  buffer closes and when Neovim exits.
- `auto_watch = true | "prompt"` — start watching linked markdown buffers as
  you open them.
- Comment commands: `:Gdoc comment`, `:Gdoc reply`, `:Gdoc resolvecomment`
  insert the CriticMarkup markers the CLI round-trips; `:Gdoc comments` puts
  every comment in the buffer into the quickfix list.
- `clipboard` setting to force or suppress the URL copy on `:Gdoc create`.
- `:checkhealth` reports the CLI version, running watchers, and unresolved
  conflicts, and errors on a pre-0.6 CLI.

### Fixed

- **`setup()` was silently discarded.** `:Gdoc` calls an `ensure_setup()` guard
  that initialises the plugin if a flag is unset — but `setup()` never claimed
  that flag, so the first `:Gdoc` command called `setup({})` and replaced the
  user's entire configuration with the defaults. A configured `cmd` fell back
  to whatever `gdoc-sync` was on `$PATH`, and `watch_interval`/`auto_watch`/
  `notify` never took effect. Present since 0.1.0; found by driving the plugin
  against a real CLI, where it silently ran an old binary.

### Changed

- `watch_interval` default 30s → 15s.
- `:Gdoc pull` offers "merge instead" when the buffer has unsaved changes, and
  mentions that the previous version was backed up.

## 0.1.0 (2026-07-17)

First release.

- `:Gdoc` with subcommand completion: create, push, pull, status, diff, open,
  share, export, link, unlink, watch, doctor — all async (the editor never
  blocks on the network)
- Drift-safe push: the CLI's optimistic-locking exit code becomes a prompt;
  `--yes` is only sent after you confirm
- Pull reloads the buffer and guards unsaved changes
- `:Gdoc watch` streams the CLI's live-sync events as notifications and
  `checktime`s so auto-pulled edits appear in the buffer
- Statusline component + linked-file cache fed by `status --json`
- `:checkhealth gdoc-sync`
- Test suite: headless module-load + functional tests against a stub CLI,
  plus an opt-in real-API E2E with isolated state
