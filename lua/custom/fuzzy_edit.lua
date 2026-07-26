--- Deep fuzzy path completion for the command line.
---
--- Neovim's built-in `:e` completion expands one path segment at a time, so
--- `lua/sna` never resolves to `lua/custom/plugins/snacks.lua`. This module
--- provides `:E`, whose completion matches the typed text as a subsequence
--- against every file path under the cwd — so `Tab` (and the wilder popup)
--- resolve deep paths inline, without opening a picker window.

local M = {}

--- Directories never worth walking. Skipping these is what keeps a scan cheap
--- enough to run from a completion function.
local SKIP_DIRS = {
  ['.git'] = true,
  ['.hg'] = true,
  ['.svn'] = true,
  ['node_modules'] = true,
  ['.venv'] = true,
  ['venv'] = true,
  ['__pycache__'] = true,
  ['.mypy_cache'] = true,
  ['.pytest_cache'] = true,
  ['.ruff_cache'] = true,
  ['target'] = true,
  ['dist'] = true,
  ['build'] = true,
  ['.next'] = true,
  ['.terraform'] = true,
}

--- How deep to walk, and how many paths to keep. Both are bounds on worst-case
--- cost in a large tree rather than limits anyone should hit day to day.
local MAX_DEPTH = 20
local MAX_FILES = 20000

--- Completion fires on every keystroke, so the file list is cached and only
--- rebuilt when the cwd changes or the entry goes stale.
local CACHE_TTL_MS = 5000

--- Number of candidates handed back to the command line. The popup is not
--- useful beyond a screenful, and trimming keeps redraws cheap.
local MAX_RESULTS = 100

---@class FuzzyEditCache
---@field cwd string|nil
---@field files string[]
---@field built_at integer Milliseconds since epoch
local cache = { cwd = nil, files = {}, built_at = 0 }

---Walk `root` and collect every file path relative to it.
---@param root string
---@return string[]
local function scan(root)
  local files = {}
  local ok, iter = pcall(vim.fs.dir, root, {
    depth = MAX_DEPTH,
    -- Returning false stops the walk from descending. Note the predicate
    -- receives a bare name only at the top level; deeper down it gets a path
    -- relative to `root` (`some-plugin/.git`), so it must be reduced to a
    -- basename or nested matches are missed.
    skip = function(dirname)
      return not SKIP_DIRS[vim.fs.basename(dirname)]
    end,
  })

  if not ok then
    return files
  end

  for name, type_ in iter do
    if type_ == 'file' then
      files[#files + 1] = name
      if #files >= MAX_FILES then
        break
      end
    end
  end

  return files
end

---The cached file list for the current directory, rebuilding when stale.
---@return string[]
function M.files()
  local cwd = vim.fn.getcwd()
  local now = vim.uv.now()

  if cache.cwd ~= cwd or (now - cache.built_at) > CACHE_TTL_MS then
    cache.cwd = cwd
    cache.files = scan(cwd)
    cache.built_at = now
  end

  return cache.files
end

---Discard the cached file list, forcing the next completion to rescan.
function M.invalidate()
  cache.cwd = nil
  cache.built_at = 0
  cache.files = {}
end

---Completion function for `:E`.
---@param arglead string The partial path typed so far
---@return string[]
function M.complete(arglead)
  local files = M.files()

  if arglead == '' then
    return vim.list_slice(files, 1, MAX_RESULTS)
  end

  -- `matchfuzzy` is Neovim's built-in subsequence matcher: it returns only
  -- matches, already ordered by score, which is exactly the ranking wanted
  -- here and considerably faster than filtering in Lua.
  local matches = vim.fn.matchfuzzy(files, arglead)
  return vim.list_slice(matches, 1, MAX_RESULTS)
end

--- RULE EXCEPTION: a global VimScript function, rather than passing
--- `M.complete` to `complete` directly. Two separate constraints force it,
--- both from wilder.nvim, which owns the `:` command line here:
---
---  1. A Lua completion function makes Neovim report the command's `complete`
---     as a Funcref. wilder's devicon drawer runs
---     `let l:expand = get(a:data, 'cmdline.expand', '')`, and VimScript
---     cannot assign a Funcref to a lowercase name — E704, on every redraw.
---     Registering as a `customlist,` string reports `"customlist"` instead.
---
---  2. wilder resolves that string with `function(l:function_name)`, which
---     cannot parse a `v:lua.` name (E15). So the string has to name a real
---     VimScript function, which then bridges back into Lua.
---
--- Silently swallowing either failure is what makes this worth pinning down:
--- wilder catches the error and then disables completion for the command for
--- the rest of the session.
local COMPLETE_FUNC = 'CustomFuzzyEditComplete'

local function define_vimscript_bridge()
  vim.cmd(([[
    function! %s(arglead, cmdline, cursorpos) abort
      return luaeval("require('custom.fuzzy_edit').complete(_A)", a:arglead)
    endfunction
  ]]):format(COMPLETE_FUNC))
end

---Register the `:E` command and keep the cache honest across directory changes.
function M.setup()
  define_vimscript_bridge()

  vim.api.nvim_create_user_command('E', function(opts)
    -- Bare `:E` mirrors bare `:edit`, which reloads the current buffer.
    if opts.args == '' then
      vim.cmd(opts.bang and 'edit!' or 'edit')
      return
    end
    vim.cmd((opts.bang and 'edit! ' or 'edit ') .. vim.fn.fnameescape(opts.args))
  end, {
    nargs = '?',
    bang = true,
    complete = 'customlist,' .. COMPLETE_FUNC,
    desc = 'Edit file, completing paths fuzzily at any depth',
  })

  -- A new cwd means an entirely different file list; don't wait for the TTL.
  vim.api.nvim_create_autocmd('DirChanged', {
    group = vim.api.nvim_create_augroup('fuzzy-edit', { clear = true }),
    callback = M.invalidate,
  })
end

return M
