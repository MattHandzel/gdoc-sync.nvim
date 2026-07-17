# Changelog

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
