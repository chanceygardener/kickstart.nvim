--- Current work context: branch, PR, base branch, Linear ticket.
---
--- One resolver shared by everything that needs to know what you're working on —
--- the diff base in `custom.review`, the ticket lookup in `custom.linear`, and the
--- statusline segment. Resolving it once in one place is the point: before this,
--- opening a diff and looking up a ticket each made their own `gh pr view` call.
---
--- Resolution is ordered by *reliability*, not by cost:
---
---   1. The PR title. `[ENG-245] do some engineering work` is the convention that
---      is actually maintained, so this is authoritative.
---   2. `linear issue id` — parses the branch name. Only reaches this for work
---      that has no PR yet, because branch names carry the ticket inconsistently.
---
--- That ordering puts a network call on the main path, which is why the cache and
--- the async priming below matter. It costs nothing extra though: the PR number
--- and base branch require `gh pr view` regardless, so the ticket falls out of a
--- request that was already happening.

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
---@param issue string
---@param owner string
---@param cb fun(prs: table[])
function M.discover(issue, owner, cb)
  if vim.fn.executable 'gh' == 0 then
    return cb {}
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
        return cb {}
      end

      local ok, rows = pcall(vim.json.decode, result.stdout or '')
      if not ok or type(rows) ~= 'table' then
        return cb {}
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

--- The story's PR for the repo the current buffer lives in, if any.
---
--- Recomputed per call rather than stored, because it depends on the buffer and a
--- stale answer would point a diff at the wrong repo. Costs one cached path
--- lookup, no subprocess.
---@return table|nil
function M.active()
  if not current then
    return nil
  end

  local r = require('custom.repo').for_buf(0)
  if not r then
    return nil
  end

  for _, pr in ipairs(current.prs or {}) do
    if pr.root == r.root or (pr.repo == r.name and pr.owner == r.owner) then
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
  end
  return nil
end

--- `ENG-1934 · #12` inside a story repo, `ENG-1934 · 3 PRs` outside one.
---@return string
function M.statusline()
  if not current then
    return ''
  end

  local active = M.active()
  if active then
    return ('%s · #%d'):format(current.issue, active.number)
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

--- Report the current story and every PR in it.
function M.show()
  local ctx = M.context()
  if not ctx then
    vim.notify('work: no current story — pick one with <leader>lw', vim.log.levels.WARN)
    return
  end

  local active = M.active()
  local lines = { ctx.issue .. (ctx.title and ('  ' .. ctx.title) or '') }

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

--- Register the commands and the refresh triggers.
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
        pcall(M.context)
      end, 200)
    end,
  })

  -- gitsigns already watches `.git/HEAD`, so this fires on checkout without any
  -- polling of our own. Both handlers compare a cached string first and do
  -- nothing when the branch is unchanged.
  vim.api.nvim_create_autocmd({ 'User', 'FocusGained' }, {
    group = group,
    pattern = '*',
    callback = function(ev)
      if ev.event == 'User' and ev.match ~= 'GitSignsUpdate' then
        return
      end
      require('custom.repo').invalidate()
    end,
  })
end

return M
