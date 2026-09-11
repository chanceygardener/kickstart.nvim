local T = require 'test.helpers'
local work = require 'custom.work'

vim.env.GH_STUB_SEARCH = '1'

local items
work.stories(function(result)
  items = result
end)
vim.wait(5000, function()
  return items ~= nil
end)

T.ok(items, 'stories returned')
T.ok(#items >= 2, 'at least two stories from the fixture')

local by_issue = {}
for _, it in ipairs(items) do
  by_issue[it.issue] = it
end

T.ok(by_issue['ENG-1934'], 'ENG-1934 present')
T.eq(by_issue['ENG-1934'].count, 4, 'PR stack counted as one story with 4 PRs')
T.ok(by_issue['DATA-441'], 'DATA-441 present')
T.eq(by_issue['DATA-441'].count, 1, 'single-PR story')

-- No duplicate rows for the same ticket.
local seen, dupes = {}, 0
for _, it in ipairs(items) do
  if seen[it.issue] then
    dupes = dupes + 1
  end
  seen[it.issue] = true
end
T.eq(dupes, 0, 'each ticket appears once')

T.done()
