--- Which repository does a buffer belong to?
---
--- Neovim is usually launched from the parent directory holding every checkout,
--- so cwd says nothing about what you are editing. Repo identity therefore comes
--- from the buffer's own path.
---
--- Results are cached per directory. Repo membership only changes when a
--- directory is created, moved, or cloned, so the cache is cleared explicitly
--- rather than on a timer.

local git = require 'custom.git'

local M = {}

---@class Repo
---@field root string absolute path to the repository root
---@field name string repository name, e.g. `kgrisk`
---@field owner string|nil GitHub owner parsed from `origin`
---@field branch string|nil current branch

--- Keyed by the directory asked about, not the repo root, because the lookup we
--- want to avoid repeating is the walk upward from an arbitrary file.
---@type table<string, Repo|false>
local cache = {}

--- The directory a path resolves to for cache purposes: itself if it already is
--- one, otherwise its parent. Shared by `for_path` and `peek_for_buf` so the two
--- always agree on what counts as a cache hit.
---@param path string
---@return string
local function cache_dir(path)
  return vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ':h')
end

---@param path string
---@return Repo|nil
function M.for_path(path)
  local dir = cache_dir(path)
  if dir == '' then
    return nil
  end

  local hit = cache[dir]
  if hit ~= nil then
    return hit or nil
  end

  local root = git.root(dir)
  if not root then
    cache[dir] = false
    return nil
  end

  local owner, name = git.remote(dir)
  local entry = {
    root = root,
    name = name or vim.fn.fnamemodify(root, ':t'),
    owner = owner,
    branch = git.branch(dir),
  }

  cache[dir] = entry
  return entry
end

--- The repo for a buffer, falling back to cwd for buffers with no file (the
--- dashboard, a scratch buffer) so the answer is still useful when it can be.
---@param bufnr? integer
---@return Repo|nil
function M.for_buf(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == '' or name:match '^%w+://' then
    return M.for_path(vim.fn.getcwd())
  end
  return M.for_path(name)
end

--- The repo for a buffer if it is already cached, without shelling out.
---
--- `for_buf` costs three `git` subprocesses on a cache miss (`root`, `remote`,
--- `branch`). A render path — the statusline redraws on essentially every
--- keystroke — cannot afford that, so it needs an answer that is either cached
--- or nil, never a fresh lookup.
---@param bufnr? integer
---@return Repo|nil
function M.peek_for_buf(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  local path = (name == '' or name:match '^%w+://') and vim.fn.getcwd() or name
  local dir = cache_dir(path)
  if dir == '' then
    return nil
  end
  local hit = cache[dir]
  return hit or nil
end

--- Drop the cache. Call after cloning or moving a checkout.
function M.invalidate()
  cache = {}
end

return M
