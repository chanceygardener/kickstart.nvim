local T = require 'test.helpers'
local repo = require 'custom.repo'

local this_repo = vim.fn.fnamemodify(vim.fn.getcwd(), ':p'):gsub('/$', '')

-- Resolve from a file inside the repo, with cwd set to the parent.
vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.fnamemodify(this_repo, ':h')))
vim.cmd('edit ' .. vim.fn.fnameescape(this_repo .. '/init.lua'))

local r = repo.for_buf(0)
T.ok(r, 'resolves a repo from the buffer path')
T.eq(r and r.root, this_repo, 'root matches')
T.eq(r and r.name, 'kickstart.nvim', 'name matches')
T.eq(r and r.owner, 'chanceygardener', 'owner matches')
T.ok(r and r.branch, 'branch present')

T.nil_(repo.for_path '/tmp', 'nil outside any repo')

-- A buffer with no file falls back to cwd, which here is not a repo.
vim.cmd 'enew'
T.nil_(repo.for_buf(0), 'nil for a fileless buffer when cwd is not a repo')

T.done()
