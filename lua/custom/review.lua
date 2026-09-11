--- Review base resolution for change-set navigation.
---
--- Every diff entry point needs an answer to one question: *review against what?*
--- Most tooling assumes `main`, which is wrong here — work happens against release
--- candidates, feature branches, and the parent branch of a stacked PR. Guessing
--- `main` silently diffs against the wrong tree, which is the failure mode that
--- wastes the most time, so this module resolves a base explicitly, tells you what
--- it picked, and lets you override it.
---
--- Resolution order:
---   1. A base you set for this branch, via `set_base` or `pick_base`.
---   2. `gh pr view` — GitHub knows the real parent of a stacked PR.
---   3. The remote's default branch, from `origin/HEAD`. Never a hardcoded `main`.
---
--- Whatever name comes back is remote-resolved: `origin/<name>` if that ref exists,
--- otherwise the bare local ref, so branches that were never pushed still work.

local git_util = require 'custom.git'

local M = {}

--- Resolved bases, keyed by `<git root>\0<branch>`. Keying on the branch as well as
--- the repo means checking out a different branch re-resolves rather than silently
--- reusing the previous branch's base — which also makes a `DirChanged` autocmd
--- unnecessary, since a stale key can never be read.
local bases = {}

--- Kept as a local alias so the resolution tiers below read as they did before the
--- git primitives moved into their own module.
local git = git_util.run

--- The cache key for the buffer's repo, or nil if the buffer is not in one.
--- Bases are keyed per repo, and the buffer's repo is not necessarily the cwd's,
--- so this always resolves through `custom.repo` rather than calling
--- `git_util.cache_key()` bare.
---@return string|nil
local function key_for_buf()
  local r = require('custom.repo').for_buf(0)
  return r and git_util.cache_key(r.root) or nil
end

--- Turn a branch name into a rev that actually exists, preferring the remote copy.
--- `--verify --quiet` exits non-zero silently when the ref is missing, so this is
--- just two existence probes.
---
--- `dir` is the buffer's repo root, not the cwd: Neovim is usually launched from
--- the parent directory holding every checkout, so a bare `git` call here would
--- silently probe the wrong (or no) repository.
---@param name string
---@param dir? string
---@return string|nil
local function remote_resolve(name, dir)
  -- `git branch --all` reports remote branches as `remotes/origin/foo`, which is a
  -- valid rev but reads badly in a Diffview title.
  name = name:gsub('^remotes/', '')

  if name:match '^origin/' then
    return git({ 'rev-parse', '--verify', '--quiet', name }, dir) and name or nil
  end

  if git({ 'rev-parse', '--verify', '--quiet', 'origin/' .. name }, dir) then
    return 'origin/' .. name
  end
  if git({ 'rev-parse', '--verify', '--quiet', name }, dir) then
    return name
  end

  return nil
end

--- The base branch for the repo the current buffer is in.
---
--- Comes from the story's PR for this repo. A story spans repos, so "the base"
--- is only meaningful relative to one of them — which is why this is keyed off
--- the buffer rather than being a property of the story.
---@return string|nil
local function pr_base()
  local active = require('custom.work').active()
  return active and active.base or nil
end

--- The remote's default branch. `origin/HEAD` is only populated if the remote was
--- cloned or `git remote set-head` has been run, so fall back to probing.
---
--- `dir` is the buffer's repo root, for the same reason `remote_resolve` takes one.
---@param dir? string
---@return string|nil
local function default_branch(dir)
  local head = git({ 'rev-parse', '--abbrev-ref', 'origin/HEAD' }, dir)
  if head then
    return head
  end

  for _, name in ipairs { 'origin/main', 'origin/master' } do
    if git({ 'rev-parse', '--verify', '--quiet', name }, dir) then
      return name
    end
  end

  return nil
end

--- The rev to diff against, resolving and caching on first use for this branch.
---@return string|nil
function M.resolve_base()
  local key = key_for_buf()
  if not key then
    vim.notify('review: not inside a git repository', vim.log.levels.WARN)
    return nil
  end

  if bases[key] then
    return bases[key]
  end

  local r = require('custom.repo').for_buf(0)
  local name = pr_base() or default_branch(r and r.root)
  local base = name and remote_resolve(name, r and r.root)
  if not base then
    vim.notify('review: could not determine a base branch — set one with <leader>db', vim.log.levels.WARN)
    return nil
  end

  bases[key] = base
  vim.notify('review base: ' .. base, vim.log.levels.INFO)
  return base
end

--- Pin a base for the current branch. Accepts anything git can resolve, including
--- tags and RC refs, not just branch names.
---@param rev string
---@return string|nil resolved
function M.set_base(rev)
  local key = key_for_buf()
  if not key then
    vim.notify('review: not inside a git repository', vim.log.levels.WARN)
    return nil
  end

  local r = require('custom.repo').for_buf(0)
  local base = remote_resolve(rev, r and r.root)
  if not base then
    vim.notify(('review: no such rev: %s'):format(rev), vim.log.levels.ERROR)
    return nil
  end

  bases[key] = base
  vim.notify('review base: ' .. base, vim.log.levels.INFO)
  return base
end

--- Drop the pinned base so the next diff re-resolves from gh/origin.
function M.clear_base()
  local key = key_for_buf()
  if key then
    bases[key] = nil
    vim.notify('review base cleared — will re-resolve', vim.log.levels.INFO)
  end
end

--- The base for the current branch if one is already resolved, without resolving.
--- Used for display, where triggering a `gh` call would be surprising.
---@return string|nil
function M.current()
  local key = key_for_buf()
  return key and bases[key] or nil
end

--- The DiffviewOpen command for the current buffer's repo, or nil.
---
--- Built as a string rather than executed so it can be asserted in a spec, and
--- because `-C{path}` has to be assembled from the repo root anyway.
---@param pathspec? string
---@return string|nil
function M.diff_command(pathspec)
  local r = require('custom.repo').for_buf(0)
  if not r then
    vim.notify('review: this buffer is not inside a git repository', vim.log.levels.WARN)
    return nil
  end

  local base = M.resolve_base()
  if not base then
    return nil
  end

  -- `-C{path}` makes Diffview run as if git started in the repo, which is what
  -- lets a diff work when Neovim's cwd is the parent directory of every checkout.
  local cmd = ('DiffviewOpen -C%s %s...HEAD'):format(vim.fn.fnameescape(r.root), base)
  if pathspec and pathspec ~= '' then
    cmd = cmd .. ' -- ' .. pathspec
  end
  return cmd
end

---@param pathspec? string
function M.open_diff(pathspec)
  local cmd = M.diff_command(pathspec)
  if cmd then
    vim.cmd(cmd)
  end
end

--- Pick a base from the branch list, then optionally open the diff against it.
---@param opts? { then_open?: boolean }
function M.pick_base(opts)
  opts = opts or {}

  Snacks.picker.git_branches {
    all = true, -- remote branches too; the base is usually not checked out locally
    confirm = function(picker, item)
      picker:close()
      if not (item and item.branch) then
        return
      end
      if M.set_base(item.branch) and opts.then_open then
        M.open_diff()
      end
    end,
  }
end

--- Narrow a large agent-generated change set without leaving the review workflow.
function M.prompt_pathspec()
  vim.ui.input({ prompt = 'Pathspec (e.g. backend/ or :!generated/): ' }, function(input)
    if input and input ~= '' then
      M.open_diff(input)
    end
  end)
end

--- The `gh dash` PR inbox in a float. This is the "which PR should I look at"
--- step that sits before everything else in this module — deliberately a terminal
--- rather than a plugin, since gh-dash is already the best version of that UI.
function M.pr_inbox()
  if vim.fn.executable 'gh' == 0 then
    vim.notify('review: gh CLI not found', vim.log.levels.ERROR)
    return
  end

  Snacks.terminal.open({ 'gh', 'dash' }, {
    win = { position = 'float', width = 0.9, height = 0.9, border = 'rounded' },
    -- Not reused across calls: gh-dash refreshes on start, and a stale dashboard
    -- from an hour ago is worse than a one-second reload.
    interactive = true,
  })
end

--- Neo-tree's git_status source against the same base. A lighter-weight look at
--- *which* files changed, when you don't want the full diff layout.
function M.git_status_tree()
  local base = M.resolve_base()
  if not base then
    return
  end
  local r = require('custom.repo').for_buf(0)
  if not r then
    return
  end
  vim.cmd(('Neotree left git_status git_base=%s dir=%s'):format(base, r.root))
end

return M
