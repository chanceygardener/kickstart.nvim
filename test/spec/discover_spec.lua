local T = require 'test.helpers'
local work = require 'custom.work'

-- group_by_issue is pure, so it needs no stub.
local rows = {
  { number = 12, title = '[ENG-1934] a', url = 'u1', repository = { name = 'kgrisk', nameWithOwner = 'acme/kgrisk' } },
  { number = 13, title = '[ENG-1934] b', url = 'u2', repository = { name = 'kgrisk', nameWithOwner = 'acme/kgrisk' } },
  { number = 91, title = '[DATA-441] c', url = 'u3', repository = { name = 'kgloader', nameWithOwner = 'acme/kgloader' } },
  { number = 99, title = 'no ticket at all', url = 'u4', repository = { name = 'kgloader', nameWithOwner = 'acme/kgloader' } },
}

local grouped = work.group_by_issue(rows)
T.eq(vim.tbl_count(grouped), 2, 'two tickets found, untitled PR ignored')
T.eq(#grouped['ENG-1934'], 2, 'PR stack groups under one ticket')
T.eq(#grouped['DATA-441'], 1, 'second ticket separate')
T.eq(grouped['ENG-1934'][1].repo, 'kgrisk', 'repo name carried through')
T.eq(grouped['ENG-1934'][1].owner, 'acme', 'owner carried through')

-- discover() against the stub.
vim.env.GH_STUB_SEARCH = '1'
local prs
work.discover('ENG-1934', 'acme', function(result)
  prs = result
end)
vim.wait(5000, function()
  return prs ~= nil
end)

T.ok(prs, 'discover returned')
T.eq(#prs, 4, 'four PRs for ENG-1934, the DATA-441 one excluded')

local by_repo = {}
for _, pr in ipairs(prs or {}) do
  by_repo[pr.repo] = (by_repo[pr.repo] or 0) + 1
end
T.eq(by_repo.kgrisk, 2, 'stack of two in one repo')
T.eq(by_repo.kgloader, 1, 'one in a second repo')
T.nil_(by_repo['no-such'], 'nothing invented')

T.done()
