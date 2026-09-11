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

-- statusline()'s warm-cache "in a story repo" form (`ENG-1934 · #12`) — the
-- headline behavior, and the path fixes 2 and 3 touch. The fixture's PRs all
-- belong to repos (kgrisk, kgloader, kg-assistant) that do not exist on this
-- machine, so nothing in it can naturally match the repo these specs run in.
-- That repo — this checkout, chanceygardener/kickstart.nvim — is already
-- resolved and cached (`set_issue` above calls `custom.repo.for_buf` to find
-- the search owner), so a PR entry for it is injected directly into the
-- already-resolved story to give `pr_for_repo`'s repo-identity match
-- something real to hit, without spawning anything extra beyond that cache
-- warm-up which already happened.
local this_repo = require('custom.repo').for_buf(0)
T.ok(this_repo, 'this checkout resolves as a repo (needed for the injected PRs below)')

if this_repo then
  local warm_ctx = work.peek()
  table.insert(warm_ctx.prs, { repo = this_repo.name, owner = this_repo.owner, number = 99, title = '[ENG-1934] warm-cache fixture' })
  T.eq(work.statusline(), 'ENG-1934 · #99', 'statusline shows PR number inside a story repo, from warm cache')
  table.remove(warm_ctx.prs) -- restore the 4-PR fixture for the assertions below

  -- active()'s branch-aware match (fix 2) and its backfill no longer being
  -- gated on `pr.root` (fix 3). test/stub/gh's headRefName is now
  -- parameterizable via GH_STUB_PR_HEAD, which lets this be deterministic
  -- rather than depending on whatever branch this checkout happens to be on.
  vim.env.GH_STUB_PR_TITLE = '[ENG-1934] irrelevant — only base/head are read'
  vim.env.GH_STUB_PR_BASE = 'release/2.1'

  -- Matching head, `root` deliberately left nil (simulating a renamed
  -- checkout/worktree `sibling_root` couldn't identify): the backfill
  -- running at all — rather than being skipped, as it was before fix 3 —
  -- is what makes this pass.
  vim.env.GH_STUB_PR_HEAD = this_repo.branch
  table.insert(warm_ctx.prs, { repo = this_repo.name, owner = this_repo.owner, number = 101, title = '[ENG-1934] head matches' })
  local active_match = work.active()
  T.ok(active_match, 'active() backfills and matches when headRefName equals the checked-out branch')
  T.eq(active_match and active_match.number, 101, 'matched PR is the injected one')
  T.eq(active_match and active_match.base, 'release/2.1', 'base backfilled via gh pr view despite pr.root being nil')
  table.remove(warm_ctx.prs)

  -- Mismatched head: same repo identity, a different PR, a head branch that
  -- is not the one checked out here. The match must be invalidated rather
  -- than diffing against the wrong PR's base.
  vim.env.GH_STUB_PR_HEAD = 'totally-unrelated-branch-xyz'
  table.insert(warm_ctx.prs, { repo = this_repo.name, owner = this_repo.owner, number = 102, title = '[ENG-1934] head mismatches' })
  T.nil_(work.active(), 'active() rejects a story PR whose headRefName differs from the checked-out branch')
  table.remove(warm_ctx.prs)

  vim.env.GH_STUB_PR_TITLE = nil
  vim.env.GH_STUB_PR_BASE = nil
  vim.env.GH_STUB_PR_HEAD = nil
end

-- peek() and statusline() must never spawn a process — including with a story
-- set and the repo cache explicitly cold, which is the exact combination that
-- would trigger a subprocess if either function reached for `active()` (repo
-- lookup) or its base-branch backfill (`gh pr view`). The cache is invalidated
-- and the counter installed together, with no uncounted call in between that
-- could quietly re-warm the cache and hide a regression.
require('custom.repo').invalidate()

local count = 0
local real = vim.system
vim.system = function(...)
  count = count + 1
  return real(...)
end

T.eq(work.statusline(), 'ENG-1934 · 4 PRs', 'statusline falls back to PR-count form on a cold repo cache')
for _ = 1, 50 do
  work.peek()
  work.statusline()
end
vim.system = real
T.eq(count, 0, 'peek/statusline spawn zero processes, even with a cold repo cache')

T.done()
