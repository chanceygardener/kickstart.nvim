local T = require 'test.helpers'
local work = require 'custom.work'

vim.env.GH_STUB_SEARCH = '1'

-- Sticky switch by ticket.
local ctx
work.set_issue('ENG-1934', function(result)
  ctx = result
end)
vim.wait(5000, function()
  return ctx ~= nil
end)

T.ok(ctx, 'set_issue resolved a context')
T.eq(ctx and ctx.issue, 'ENG-1934', 'issue set')
T.eq(ctx and #ctx.prs, 4, 'story carries all its PRs')
T.ok(ctx and ctx.searched_at and ctx.searched_at > 0, 'searched_at recorded')

-- Stickiness: peek does not change when the buffer does.
vim.cmd 'enew'
T.eq(work.peek() and work.peek().issue, 'ENG-1934', 'ticket sticky across buffers')

-- active() is nil when the buffer is not in one of the story's repos.
T.nil_(work.active(), 'no active PR outside the story repos')
T.eq(work.statusline(), 'ENG-1934 · 4 PRs', 'statusline shows PR count outside story repos')

-- Switching back and forth is cached.
work.set_issue 'DATA-441'
vim.wait(5000, function()
  return work.peek() and work.peek().issue == 'DATA-441'
end)
T.eq(work.peek().issue, 'DATA-441', 'switched story')

work.set_issue 'ENG-1934'
vim.wait(5000, function()
  return work.peek() and work.peek().issue == 'ENG-1934'
end)
T.eq(work.peek().issue, 'ENG-1934', 'switched back')

-- peek() and statusline() must never spawn a process.
local count = 0
local real = vim.system
vim.system = function(...)
  count = count + 1
  return real(...)
end
for _ = 1, 50 do
  work.peek()
  work.statusline()
end
vim.system = real
T.eq(count, 0, 'peek/statusline spawn zero processes')

T.done()
