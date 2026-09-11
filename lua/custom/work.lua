--- Current work context: a sticky ticket and every open PR implementing it,
--- across repos.
---
--- Work spans several repos with no monorepo, so "what am I working on" cannot
--- be answered from one repo's branch — it has to be answered from the ticket,
--- with `active()` picking out whichever of the story's PRs belongs to the repo
--- the current buffer is in. One resolver shared by everything that needs this —
--- the diff base in `custom.review`, the ticket lookup in `custom.linear`, and
--- the statusline segment.
---
--- A story is found in one of two ways:
---
---   1. Explicitly, via `set_issue`/`:WorkSwitch` — you name the ticket.
---   2. Implicitly, via `context()`: the current buffer's repo's own PR title
---      names a ticket (`[ENG-245] do some engineering work`), or, pre-PR, the
---      branch name via `linear issue id`. That ticket then becomes the story,
---      widened to every PR across every repo that implements it.
---
--- Once a story is current, it is cached by ticket for the rest of the session —
--- switching back to one you were on ten minutes ago does not re-search GitHub.

local git = require 'custom.git'

local M = {}

--- Contexts already resolved this session, keyed by ticket. Switching back to a
--- story you were on ten minutes ago should not re-search GitHub.
---@type table<string, table>
local stories = {}

--- The sticky current story. One at a time, by design: switching re-points the
--- ticket, its PRs, the diff base and the statusline, and leaves your windows
--- alone.
---@type table|nil
local current = nil

--- Guards against overlapping resolves stacking up `gh` invocations.
local resolving = false

--- Pull a Linear issue identifier out of arbitrary text.
---
--- Deliberately does not assume a team key: a repo is often worked by several
--- Linear teams, so `ENG` is only one of the keys that shows up. Brackets are
--- optional since not every title follows the convention exactly.
---@param text string|nil
---@return string|nil
function M.parse_identifier(text)
  if not text or text == '' then
    return nil
  end

  -- Prefer a bracketed match — that's the convention, and it avoids matching
  -- something incidental later in the title.
  local id = text:match '%[([A-Za-z][A-Za-z0-9]*%-%d+)%]' or text:match '([A-Za-z][A-Za-z0-9]*%-%d+)'
  return id and id:upper() or nil
end

--- Where a discovered repo lives on disk, if it is checked out beside the one we
--- are already in.
---
--- The remote is re-checked rather than trusting the directory name, so a
--- coincidentally-named sibling cannot be adopted into a story.
---@param name string
---@param owner string
---@param near string|nil an existing repo root to look beside
---@return string|nil
local function sibling_root(name, owner, near)
  if not near then
    return nil
  end

  local candidate = vim.fn.fnamemodify(near, ':h') .. '/' .. name
  if vim.fn.isdirectory(candidate) ~= 1 then
    return nil
  end

  local got_owner, got_name = git.remote(candidate)
  if got_owner == owner and got_name == name then
    return candidate
  end
  return nil
end

--- Group raw `gh search prs` rows by the ticket in their titles.
---
--- Several PRs for one ticket is the normal stacked-PR case, so this returns a
--- list per ticket rather than a single PR. Rows whose title carries no
--- identifier are dropped — they are not part of any story we can name.
---@param rows table[]
---@param near? string a repo root to resolve sibling checkouts against
---@return table<string, table[]>
function M.group_by_issue(rows, near)
  local grouped = {}

  for _, row in ipairs(rows or {}) do
    local issue = M.parse_identifier(row.title)
    if issue then
      local full = row.repository and row.repository.nameWithOwner or ''
      local owner = full:match '^([^/]+)/' or ''
      local name = row.repository and row.repository.name or full:match '/(.+)$' or ''

      grouped[issue] = grouped[issue] or {}
      table.insert(grouped[issue], {
        repo = name,
        owner = owner,
        number = row.number,
        title = row.title,
        url = row.url,
        root = sibling_root(name, owner, near),
      })
    end
  end

  return grouped
end

--- Every open PR whose title names `issue`, across the owner's repos.
---
--- One search rather than a walk over sibling directories: the title convention
--- is reliable, and a repo with work but no PR is not part of a story we can
--- discover anyway.
---
--- `nil` means the search itself could not be attempted or trusted — no `gh`, a
--- non-zero exit, or unparseable output. An empty list means the search ran and
--- genuinely found nothing. Callers must not treat the two as the same: caching
--- a transient `gh` failure as "0 PRs" would turn one bad network call into a
--- permanently wrong answer for that ticket.
---@param issue string
---@param owner string
---@param cb fun(prs: table[]|nil)
function M.discover(issue, owner, cb)
  if vim.fn.executable 'gh' == 0 then
    return cb(nil)
  end

  local near = (require('custom.repo').for_buf(0) or {}).root

  -- RULE EXCEPTION: async form of vim.system, as elsewhere in this module. A
  -- cross-repo search is slower than a single `gh pr view` and this runs on
  -- context switches, where blocking would be felt immediately.
  vim.system(
    { 'gh', 'search', 'prs', ('[%s]'):format(issue), '--owner', owner, '--state', 'open', '--json', 'number,title,url,repository' },
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        return cb(nil)
      end

      local ok, rows = pcall(vim.json.decode, result.stdout or '')
      if not ok or type(rows) ~= 'table' then
        return cb(nil)
      end

      cb(M.group_by_issue(rows, near)[issue] or {})
    end)
  )
end

--- Make `issue` the current story, resolving its PRs if not already known.
---@param issue string
---@param cb? fun(ctx: table|nil)
function M.set_issue(issue, cb)
  cb = cb or function() end
  issue = issue:upper()

  local cached = stories[issue]
  if cached then
    current = cached
    return cb(cached)
  end

  if resolving then
    return cb(nil)
  end
  resolving = true

  local owner = (require('custom.repo').for_buf(0) or {}).owner
  if not owner then
    resolving = false
    vim.notify('work: cannot tell which GitHub owner to search — open a file in a repo first', vim.log.levels.WARN)
    return cb(nil)
  end

  M.discover(issue, owner, function(prs)
    resolving = false

    -- A nil result means the search failed or couldn't be attempted, not that
    -- the ticket has no PRs. Do not cache that as a definitive answer — an
    -- outage would otherwise become a permanent "0 PRs" for this ticket.
    if not prs then
      return cb(nil)
    end

    local ctx = { issue = issue, prs = prs, searched_at = os.time() * 1000 }
    stories[issue] = ctx
    current = ctx
    cb(ctx)
  end)
end

--- The current story, resolving one from the buffer's repo if none is set.
---@return table|nil
function M.context()
  if current then
    return current
  end

  local r = require('custom.repo').for_buf(0)
  if not r then
    return nil
  end

  -- Derive a starting ticket from this repo's PR, then let set_issue expand it
  -- into the full story.
  local issue = M.issue_for_repo(r)
  if not issue then
    return nil
  end

  local done = false
  M.set_issue(issue, function()
    done = true
  end)
  vim.wait(5000, function()
    return done
  end)

  return current
end

--- Retained so existing callers in review.lua and linear.lua keep working.
---@return table|nil
function M.get()
  return M.context()
end

--- The current story without resolving anything. Safe on a render path.
---@return table|nil
function M.peek()
  return current
end

--- The story's PR whose repo identity matches `r`, without any base-branch
--- backfill.
---
--- Shared by `active()`, which backfills a missing base and may shell out, and
--- `statusline()`, which must not do either — pulling the match itself out into
--- a pure lookup keeps that difference from duplicating the matching logic.
---@param r table a Repo from custom.repo
---@return table|nil
local function pr_for_repo(r)
  for _, pr in ipairs((current or {}).prs or {}) do
    if pr.root == r.root or (pr.repo == r.name and pr.owner == r.owner) then
      return pr
    end
  end
  return nil
end

--- The story's PR for the repo the current buffer lives in, if any.
---
--- Recomputed per call rather than stored, because it depends on the buffer and a
--- stale answer would point a diff at the wrong repo. May shell out: a cold
--- repo cache costs the `git` calls behind `custom.repo.for_buf`, and a PR whose
--- base branch isn't known yet costs one `gh pr view`. Fine from a keymap or
--- command; never call this from a render path — use `statusline()` there.
---@return table|nil
function M.active()
  if not current then
    return nil
  end

  local r = require('custom.repo').for_buf(0)
  if not r then
    return nil
  end

  local pr = pr_for_repo(r)
  if not pr then
    return nil
  end

  if not pr.base and pr.root then
    local result = vim.system({
      'gh', 'pr', 'view', tostring(pr.number),
      '--repo', ('%s/%s'):format(pr.owner, pr.repo),
      '--json', 'baseRefName', '--jq', '.baseRefName',
    }, { text = true }):wait()
    if result.code == 0 then
      pr.base = vim.trim(result.stdout or '')
    end
  end

  return pr
end

--- `ENG-1934 · #12` inside a story repo, `ENG-1934 · 3 PRs` outside one.
---
--- Cache-only, like `peek()`: reads the buffer's repo through
--- `custom.repo.peek_for_buf`, which answers from cache or not at all, and never
--- calls `active()`, which can shell out to backfill a base branch. A cold repo
--- cache just falls back to the PR-count form rather than spawning anything —
--- this runs on essentially every redraw and must never touch a subprocess.
---@return string
function M.statusline()
  if not current then
    return ''
  end

  local r = require('custom.repo').peek_for_buf(0)
  local pr = r and pr_for_repo(r)
  if pr then
    return ('%s · #%d'):format(current.issue, pr.number)
  end

  local n = #(current.prs or {})
  if n == 0 then
    return current.issue
  end
  return ('%s · %d PR%s'):format(current.issue, n, n == 1 and '' or 's')
end

--- The ticket for a single repo, from its PR title, falling back to the branch.
---@param r table a Repo from custom.repo
---@return string|nil
function M.issue_for_repo(r)
  if vim.fn.executable 'gh' == 1 and r.owner then
    local result = vim.system({
      'gh', 'pr', 'view',
      '--repo', ('%s/%s'):format(r.owner, r.name),
      '--json', 'number,title,baseRefName,url',
    }, { text = true, cwd = r.root }):wait()

    if result.code == 0 then
      local ok, pr = pcall(vim.json.decode, result.stdout or '')
      if ok and pr and pr.title then
        local issue = M.parse_identifier(pr.title)
        if issue then
          return issue
        end
      end
    end
  end

  -- Pre-PR fallback: the branch name, via the Linear CLI's local parse.
  if vim.fn.executable 'linear' == 1 then
    local result = vim.system({ 'linear', 'issue', 'id' }, { text = true, cwd = r.root }):wait()
    if result.code == 0 then
      return M.parse_identifier(vim.trim(result.stdout or ''))
    end
  end

  return nil
end

--- Run one `gh search prs` query, returning raw rows.
---@param args string[]
---@param cb fun(rows: table[])
local function search(args, cb)
  if vim.fn.executable 'gh' == 0 then
    return cb {}
  end

  local cmd = { 'gh', 'search', 'prs', '--state', 'open', '--json', 'number,title,url,repository' }
  vim.list_extend(cmd, args)

  -- RULE EXCEPTION: async form of vim.system, as elsewhere in this module. The
  -- switcher runs two of these queries on demand and must not freeze the editor
  -- while they're in flight.
  vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      return cb {}
    end
    local ok, rows = pcall(vim.json.decode, result.stdout or '')
    cb(ok and type(rows) == 'table' and rows or {})
  end))
end

--- Stories worth switching to: yours, ones awaiting your review, and ones you
--- already visited this session.
---
--- Rows are tickets rather than PRs, so a stack shows up once with a count.
---@param cb fun(items: table[])
function M.stories(cb)
  local owner = (require('custom.repo').for_buf(0) or {}).owner
  local scope = owner and { '--owner', owner } or {}

  local mine, review_requested
  local function finish()
    if not (mine and review_requested) then
      return
    end

    local items, seen = {}, {}
    local function add(rows, source)
      for issue, prs in pairs(M.group_by_issue(rows)) do
        if not seen[issue] then
          seen[issue] = true
          items[#items + 1] = {
            issue = issue,
            title = (prs[1].title:gsub('^%s*%[[^%]]+%]%s*', '')),
            count = #prs,
            source = source,
            current = current ~= nil and current.issue == issue,
            text = issue .. ' ' .. (prs[1].title or ''),
          }
        end
      end
    end

    add(mine, 'mine')
    add(review_requested, 'review')

    for issue, ctx in pairs(stories) do
      if not seen[issue] then
        seen[issue] = true
        items[#items + 1] = {
          issue = issue,
          title = ctx.title or '',
          count = #(ctx.prs or {}),
          source = 'recent',
          current = current ~= nil and current.issue == issue,
          text = issue .. ' ' .. (ctx.title or ''),
        }
      end
    end

    table.sort(items, function(a, b)
      if a.current ~= b.current then
        return a.current
      end
      return a.issue < b.issue
    end)

    cb(items)
  end

  local mine_args = vim.list_extend({ '--author', '@me' }, vim.deepcopy(scope))
  local review_args = vim.list_extend({ '--review-requested', '@me' }, vim.deepcopy(scope))

  search(mine_args, function(rows)
    mine = rows
    finish()
  end)
  search(review_args, function(rows)
    review_requested = rows
    finish()
  end)
end

--- Pick a story and switch to it.
function M.switch()
  M.stories(function(items)
    if #items == 0 then
      vim.notify('work: no open stories found', vim.log.levels.WARN)
      return
    end

    Snacks.picker {
      title = 'Switch story',
      items = items,
      format = function(item)
        return {
          { item.current and '● ' or '  ', 'SnacksPickerLabel' },
          { ('%-10s'):format(item.issue), 'SnacksPickerLabel' },
          { ' ' .. item.title, 'SnacksPickerFile' },
          { ('  %d PR%s'):format(item.count, item.count == 1 and '' or 's'), 'SnacksPickerComment' },
          { '  ' .. item.source, 'SnacksPickerComment' },
        }
      end,
      preview = function(ctx)
        return Snacks.picker.preview.cmd({ 'linear', 'issue', 'view', ctx.item.issue }, ctx, { ft = 'markdown' })
      end,
      confirm = function(picker, item)
        picker:close()
        if item then
          M.set_issue(item.issue, function()
            M.show()
          end)
        end
      end,
    }
  end)
end

--- Report the current story and every PR in it.
function M.show()
  local ctx = M.context()
  if not ctx then
    vim.notify('work: no current story — pick one with <leader>lw', vim.log.levels.WARN)
    return
  end

  local active = M.active()
  local lines = { ctx.issue }

  for _, pr in ipairs(ctx.prs or {}) do
    local marker = (active and active.number == pr.number and active.repo == pr.repo) and '>' or ' '
    local where = pr.root and '' or '  (not cloned)'
    lines[#lines + 1] = ('%s %s #%d%s'):format(marker, pr.repo, pr.number, where)
  end

  if #(ctx.prs or {}) == 0 then
    lines[#lines + 1] = '  no open PRs found for this ticket'
  end

  local age = math.floor((os.time() * 1000 - (ctx.searched_at or 0)) / 1000)
  lines[#lines + 1] = ('  searched %ds ago — <leader>lr to refresh'):format(age)

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO, { title = 'work context' })
end

--- Re-search the current story.
function M.refresh()
  local ctx = current
  if not ctx then
    vim.notify('work: no current story to refresh', vim.log.levels.WARN)
    return
  end

  stories[ctx.issue] = nil
  M.set_issue(ctx.issue, function()
    M.show()
  end)
end

--- Prime the current story from the buffer's repo, without blocking.
---
--- Startup-only best effort: it takes just the PR-title path, skipping the
--- `linear issue id` fallback `issue_for_repo` also has, since a pre-PR branch
--- is exactly the case where there is nothing useful to show before you've
--- asked for anything. `context()` still covers that path on demand.
---
--- RULE EXCEPTION: async form of vim.system, as `M.discover` uses elsewhere in
--- this module. This runs 200ms after VimEnter, and a cold `gh pr view` is
--- 300ms-2s — `issue_for_repo`'s sync `:wait()` is fine from a keymap, but
--- would stall the UI right after startup.
local function prime_from_buffer()
  if current or vim.fn.executable 'gh' == 0 then
    return
  end

  local r = require('custom.repo').for_buf(0)
  if not r or not r.owner then
    return
  end

  vim.system(
    { 'gh', 'pr', 'view', '--repo', ('%s/%s'):format(r.owner, r.name), '--json', 'number,title,baseRefName,url' },
    { text = true, cwd = r.root },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        return
      end

      local ok, pr = pcall(vim.json.decode, result.stdout or '')
      if not ok or not pr or not pr.title then
        return
      end

      local issue = M.parse_identifier(pr.title)
      if issue then
        M.set_issue(issue)
      end
    end)
  )
end

--- Register the commands and the startup priming.
function M.setup()
  vim.api.nvim_create_user_command('WorkContext', function()
    M.show()
  end, { desc = 'Show the resolved work context' })

  vim.api.nvim_create_user_command('WorkContextRefresh', function()
    M.refresh()
  end, { desc = 'Re-resolve the work context' })

  vim.api.nvim_create_user_command('WorkSwitch', function(cmd)
    if cmd.args ~= '' then
      M.set_issue(cmd.args, function()
        M.show()
      end)
    else
      M.switch()
    end
  end, { nargs = '?', desc = 'Switch the current story' })

  -- Its own augroup: `custom.fuzzy_edit` clears `fuzzy-edit` on setup, and any
  -- shared name would wipe whichever registered first.
  local group = vim.api.nvim_create_augroup('work-context', { clear = true })

  -- Prime after the UI is up, so a cold `gh pr view` never delays startup.
  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    callback = function()
      vim.defer_fn(function()
        pcall(prime_from_buffer)
      end, 200)
    end,
  })
end

return M
