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

--- Resolved contexts, keyed by `<root>\0<branch>`. See `custom.git.cache_key`.
---@type table<string, table>
local contexts = {}

--- The most recent resolution, for render paths that must not touch the
--- filesystem. Separate from `contexts` because reading that requires building a
--- key, which costs two subprocesses.
---@type table|nil
local last = nil

--- Whether a resolve is already in flight, so overlapping triggers (a branch
--- change that also fires FocusGained) don't stack up `gh` invocations.
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

--- The branch, cheaply. Prefers gitsigns, which already watches `.git/HEAD`, so
--- the common case costs nothing.
---@return string|nil
local function cheap_branch()
  local head = vim.g.gitsigns_head
  if head and head ~= '' then
    return head
  end
  return git.branch()
end

--- The ticket from the branch name, via the Linear CLI. Local parse only — no
--- network, no auth — so this is safe to call on any resolve.
---@return string|nil
local function branch_issue()
  if vim.fn.executable 'linear' == 0 then
    return nil
  end

  -- Non-zero here is the ordinary "branch has no issue id" case, not a failure.
  local result = vim.system({ 'linear', 'issue', 'id' }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  return M.parse_identifier(vim.trim(result.stdout or ''))
end

--- Build a context table from a decoded `gh pr view` payload plus the branch.
---@param branch string|nil
---@param pr table|nil
---@return table
local function build(branch, pr)
  local ctx = { branch = branch }

  if pr then
    ctx.pr = pr.number
    ctx.pr_title = pr.title
    ctx.pr_url = pr.url
    ctx.base = pr.baseRefName
    ctx.issue = M.parse_identifier(pr.title)
  end

  -- Only consult the branch when the PR didn't supply a ticket. When both exist
  -- and disagree the PR wins, but the disagreement is recorded rather than
  -- discarded — it usually means a branch was reused or cut for a neighbouring
  -- ticket in a stack, and quietly showing the wrong requirements next to a diff
  -- is exactly the failure this module exists to prevent.
  local from_branch = branch_issue()
  if ctx.issue and from_branch and from_branch ~= ctx.issue then
    ctx.issue_conflict = from_branch
  elseif not ctx.issue then
    ctx.issue = from_branch
  end

  return ctx
end

--- Fetch the PR for the current branch. `nil` means no PR, which is ordinary.
---@param cb fun(pr: table|nil)
local function fetch_pr(cb)
  if vim.fn.executable 'gh' == 0 then
    return cb(nil)
  end

  -- RULE EXCEPTION: this is the one place in the config that uses the async form
  -- of `vim.system` rather than the `:wait()` idiom used elsewhere. A cold
  -- `gh pr view` is 300ms-2s, and this runs on VimEnter and on every branch
  -- change — blocking there would stall startup and stutter redraws.
  vim.system(
    { 'gh', 'pr', 'view', '--json', 'number,title,baseRefName,headRefName,url' },
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        return cb(nil)
      end

      local ok, decoded = pcall(vim.json.decode, result.stdout or '')
      cb(ok and decoded or nil)
    end)
  )
end

--- Resolve the context for the current branch, off the main path.
---@param opts? { force?: boolean, notify?: boolean }
---@param cb? fun(ctx: table|nil)
function M.resolve(opts, cb)
  opts = opts or {}
  cb = cb or function() end

  local key = git.cache_key()
  if not key then
    return cb(nil)
  end

  if contexts[key] and not opts.force then
    last = contexts[key]
    return cb(contexts[key])
  end

  if resolving then
    return cb(contexts[key])
  end
  resolving = true

  local branch = cheap_branch()
  fetch_pr(function(pr)
    resolving = false

    local ctx = build(branch, pr)
    contexts[key] = ctx
    last = ctx

    if opts.notify and ctx.issue_conflict then
      vim.notify(
        ('work: branch suggests %s but the PR title says %s — using %s'):format(ctx.issue_conflict, ctx.issue, ctx.issue),
        vim.log.levels.WARN
      )
    end

    cb(ctx)
  end)
end

--- The context for the current branch, resolving synchronously if it isn't cached.
--- Use from keymaps and commands, never from a render path.
---@return table|nil
function M.get()
  local key = git.cache_key()
  if not key then
    vim.notify('work: not inside a git repository', vim.log.levels.WARN)
    return nil
  end

  if contexts[key] then
    last = contexts[key]
    return contexts[key]
  end

  -- No cached answer, and the caller wants one now. Drive the async resolve to
  -- completion rather than duplicating it in a synchronous form.
  local done = false
  M.resolve({ notify = true }, function()
    done = true
  end)
  vim.wait(5000, function()
    return done
  end)

  return contexts[key]
end

--- The last resolved context, without resolving anything.
---
--- Issues no subprocess and touches no network, so it is safe to call on every
--- statusline redraw. Returns nil until the first resolve lands.
---@return table|nil
function M.peek()
  return last
end

--- Drop the cached context for this branch and resolve it again.
function M.refresh()
  local key = git.cache_key()
  if key then
    contexts[key] = nil
  end

  M.resolve({ force = true, notify = true }, function(ctx)
    if ctx then
      M.show()
    else
      vim.notify('work: could not resolve a work context here', vim.log.levels.WARN)
    end
  end)
end

--- A one-line summary for the statusline. Cache-only; empty when nothing is known.
---@return string
function M.statusline()
  local ctx = last
  if not ctx then
    return ''
  end

  local parts = {}
  if ctx.issue then
    parts[#parts + 1] = ctx.issue
  end
  if ctx.pr then
    parts[#parts + 1] = '#' .. ctx.pr
  end

  return table.concat(parts, ' · ')
end

--- Report the resolved context.
function M.show()
  local ctx = M.get()
  if not ctx then
    return
  end

  local lines = {}
  if ctx.pr then
    lines[#lines + 1] = ('PR #%d  %s'):format(ctx.pr, ctx.pr_title or '')
  else
    lines[#lines + 1] = 'no open PR for this branch'
  end

  if ctx.issue then
    lines[#lines + 1] = 'issue:  ' .. ctx.issue
  else
    lines[#lines + 1] = 'issue:  none found'
  end

  if ctx.issue_conflict then
    lines[#lines + 1] = ('        (branch suggests %s — PR title wins)'):format(ctx.issue_conflict)
  end

  lines[#lines + 1] = 'base:   ' .. (ctx.base or 'unknown')
  lines[#lines + 1] = 'branch: ' .. (ctx.branch or 'unknown')

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO, { title = 'work context' })
end

--- Register the commands and the refresh triggers.
function M.setup()
  vim.api.nvim_create_user_command('WorkContext', function()
    M.show()
  end, { desc = 'Show the resolved work context' })

  vim.api.nvim_create_user_command('WorkContextRefresh', function()
    M.refresh()
  end, { desc = 'Re-resolve the work context' })

  -- Its own augroup: `custom.fuzzy_edit` clears `fuzzy-edit` on setup, and any
  -- shared name would wipe whichever registered first.
  local group = vim.api.nvim_create_augroup('work-context', { clear = true })

  -- Prime after the UI is up, so a cold `gh pr view` never delays startup.
  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    callback = function()
      vim.defer_fn(function()
        M.resolve()
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
      if last and last.branch == cheap_branch() then
        return
      end
      M.resolve()
    end,
  })
end

return M
