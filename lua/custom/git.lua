--- Shared git primitives for the modules that need repo context.
---
--- Extracted from `custom.review` once `custom.work` needed the same three things:
--- run a git command, find the repo root, and build a cache key. Nothing here is
--- specific to reviewing or to Linear.
---
--- The contract throughout is that `nil` means "unknown" — never an error. Callers
--- decide whether an unknown is worth reporting, which keeps the resolution tiers
--- in the modules above able to fall through quietly.

local M = {}

--- Run git, returning trimmed stdout, or nil if it failed or produced nothing.
---@param args string[]
---@return string|nil
function M.run(args)
  local cmd = { 'git' }
  vim.list_extend(cmd, args)

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local out = vim.trim(result.stdout or '')
  return out ~= '' and out or nil
end

---@return string|nil
function M.root()
  return M.run { 'rev-parse', '--show-toplevel' }
end

---@return string|nil
function M.branch()
  return M.run { 'rev-parse', '--abbrev-ref', 'HEAD' }
end

--- Key for anything cached per repo-and-branch, as `<root>\0<branch>`.
---
--- Keying on the branch as well as the repo is what makes cache invalidation a
--- non-problem: checking out a different branch changes the key, so a stale entry
--- becomes unreachable rather than wrong. No `DirChanged` watcher is needed to
--- keep a cache *correct* — watchers are only for refreshing it eagerly.
---
--- Costs two subprocesses (~2-5ms). Fine on a keymap, too much on a render path;
--- see `custom.work.peek` for the display-safe alternative.
---@return string|nil
function M.cache_key()
  local root = M.root()
  if not root then
    return nil
  end
  return root .. '\0' .. (M.branch() or '?')
end

return M
