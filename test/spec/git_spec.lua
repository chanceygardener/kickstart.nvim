local T = require 'test.helpers'
local git = require 'custom.git'

local this_repo = vim.fn.fnamemodify(vim.fn.getcwd(), ':p'):gsub('/$', '')

-- Path-aware lookups work regardless of cwd.
vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.fnamemodify(this_repo, ':h')))
T.nil_(git.root(), 'root() is nil from the parent directory')
T.eq(git.root(this_repo), this_repo, 'root(dir) resolves from the parent directory')
T.ok(git.branch(this_repo), 'branch(dir) resolves from the parent directory')
T.ok(git.cache_key(this_repo), 'cache_key(dir) resolves from the parent directory')

local owner, name = git.remote(this_repo)
T.eq(owner, 'chanceygardener', 'remote owner parsed')
T.eq(name, 'kickstart.nvim', 'remote name parsed')

T.nil_(git.root '/tmp', 'root() nil outside any repo')

T.done()
