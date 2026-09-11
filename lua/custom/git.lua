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
---
--- `dir` matters more than it looks: Neovim is often launched from the parent
--- directory holding several checkouts, so resolving against the cwd finds no
--- repository at all. Callers pass the directory of the buffer they care about.
---@param args string[]
---@param dir? string run as if git started here
---@return string|nil
function M.run(args, dir)
  local cmd = { 'git' }
  if dir then
    table.insert(cmd, '-C')
    table.insert(cmd, dir)
  end
  vim.list_extend(cmd, args)

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local out = vim.trim(result.stdout or '')
  return out ~= '' and out or nil
end

---@param dir? string
---@return string|nil
function M.root(dir)
  return M.run({ 'rev-parse', '--show-toplevel' }, dir)
end

---@param dir? string
---@return string|nil
function M.branch(dir)
  return M.run({ 'rev-parse', '--abbrev-ref', 'HEAD' }, dir)
end

--- Owner and repository name from the `origin` remote, for both SSH and HTTPS
--- forms. Used to scope a cross-repo PR search without any configuration.
---@param dir? string
---@return string|nil owner
---@return string|nil name
function M.remote(dir)
  local url = M.run({ 'remote', 'get-url', 'origin' }, dir)
  if not url then
    return nil, nil
  end

  local owner, name = url:match '[:/]([^/:]+)/([^/]-)%.git$'
  if not owner then
    owner, name = url:match '[:/]([^/:]+)/([^/]+)$'
  end
  return owner, name
end

--- Key for anything cached per repo-and-branch, as `<root>\0<branch>`.
---
--- Keying on the branch as well as the repo is what makes cache invalidation a
--- non-problem: checking out a different branch changes the key, so a stale entry
--- becomes unreachable rather than wrong.
---@param dir? string
---@return string|nil
function M.cache_key(dir)
  local root = M.root(dir)
  if not root then
    return nil
  end
  return root .. '\0' .. (M.branch(dir) or '?')
end

return M
