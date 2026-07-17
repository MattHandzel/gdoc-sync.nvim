-- Minimal init for headless tests: only this plugin on the runtimepath.
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime! plugin/gdoc-sync.lua")
