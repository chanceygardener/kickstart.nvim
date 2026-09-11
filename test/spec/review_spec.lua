local T = require 'test.helpers'
local review = require 'custom.review'
local work = require 'custom.work'

vim.env.GH_STUB_SEARCH = '1'

-- With no story, the command still works off the repo's own base.
vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.getcwd() .. '/init.lua'))
local cmd = review.diff_command()
T.ok(cmd, 'builds a command for the current repo')
T.ok(cmd and cmd:match '%-C', 'command carries -C so it works from a parent cwd')
T.ok(cmd and cmd:match '%.%.%.HEAD', 'three-dot range')

-- Pathspec is appended after a separator.
local filtered = review.diff_command 'lua/'
T.ok(filtered and filtered:match '%-%- lua/$', 'pathspec appended')

T.done()
