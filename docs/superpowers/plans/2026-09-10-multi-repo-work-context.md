# Multi-Repo Work Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Linear/work-context integration work when Neovim runs from `~/repos`, and re-anchor context on the Linear ticket plus every PR implementing it across repos.

**Architecture:** Git lookups become buffer-relative (`git -C <dir>`) instead of cwd-relative. A new `custom.repo` maps a buffer to its repo. `custom.work` is restructured around a sticky ticket whose `prs` list is discovered with one `gh search prs` scoped to the org derived from the current repo's remote; `active` is the PR for the buffer's repo. Diffs target any repo via Diffview's `-C{path}`.

**Tech Stack:** Lua (Neovim 0.12), `gh` CLI, `schpet/linear-cli`, snacks.nvim picker, bash test stubs.

**Spec:** `docs/superpowers/specs/2026-09-10-multi-repo-work-context-design.md`

## Global Constraints

- Neovim **0.12.0+**. Lua only; no new plugins.
- Style per `.stylua.toml`: 2-space indent, single quotes, 160 columns, **no call parentheses** for single string/table args (`require 'custom.git'`).
- **Never run stylua across existing files** — the repo is hand-aligned and stylua churns ~100 unrelated lines. Match surrounding style by hand.
- Notifications use the house convention `'module: message'` via `vim.notify` (snacks owns it).
- Process idiom: sync `vim.system(args, { text = true }):wait()`; `nil` means "unknown", never an error. Only top-level public functions notify. Probe binaries with `vim.fn.executable 'x' == 0`.
- **Exception:** anything on a render path or startup path uses the async callback form of `vim.system` and must carry a comment saying why, per CLAUDE.md's rule-exception convention.
- Timestamps are **integer milliseconds** since epoch (`vim.uv.now()` is monotonic; use `os.time() * 1000` for wall clock).
- LuaCATS annotations (`---@param`, `---@return`) on public functions.
- `peek()` and `statusline()` must issue **zero** subprocesses. This is asserted by a test, not assumed.

---

## File Structure

| File | Responsibility |
|---|---|
| `test/helpers.lua` | **new** — assertion helpers + result reporting for `nvim -l` specs |
| `test/run.sh` | **new** — runs every `test/spec/*.lua`, aggregates, exits non-zero on failure |
| `test/spec/*.lua` | **new** — one spec file per module under test |
| `test/stub/gh` | extend — add `search prs` |
| `lua/custom/git.lua` | add optional directory arg; add remote parsing |
| `lua/custom/repo.lua` | **new** — buffer path → repo identity, cached |
| `lua/custom/work.lua` | restructure — sticky ticket, cross-repo PR set, switcher |
| `lua/custom/review.lua` | base from `work.active()`; `-C<root>` on Diffview |
| `init.lua` | two new keymaps, one new command |
| `CHEATSHEET.md` / `README.md` | document the multi-repo model |

---

### Task 1: Test harness

No test runner exists today. Every later task is TDD, so this comes first. Uses
`nvim -l script.lua`, which loads the user config, runs the script, and propagates
the exit code — verified working, no plugin needed.

**Files:**
- Create: `test/helpers.lua`
- Create: `test/run.sh`
- Create: `test/spec/parse_identifier_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `require('test.helpers')` returning `{ eq, ok, nil_, done }`.
  - `T.eq(actual, expected, label)` — records pass/fail
  - `T.ok(value, label)` — truthy check
  - `T.nil_(value, label)` — explicit nil check
  - `T.done()` — prints summary, `os.exit(1)` if any failed, else `os.exit(0)`

- [ ] **Step 1: Write the harness**

Create `test/helpers.lua`:

```lua
--- Minimal assertions for specs run under `nvim -l`.
---
--- `nvim -l` loads the real config, so specs exercise modules exactly as they
--- behave in a live session. No plugin or external runner is involved.

local M = {}

local failures = 0
local total = 0

---@param label string
---@param passed boolean
---@param detail? string
local function record(label, passed, detail)
  total = total + 1
  if passed then
    io.write('  ok   ', label, '\n')
  else
    failures = failures + 1
    io.write('  FAIL ', label, detail and ('  -> ' .. detail) or '', '\n')
  end
end

---@param actual any
---@param expected any
---@param label string
function M.eq(actual, expected, label)
  record(label, actual == expected, ('expected %s, got %s'):format(vim.inspect(expected), vim.inspect(actual)))
end

---@param value any
---@param label string
function M.ok(value, label)
  record(label, value and true or false, ('expected truthy, got %s'):format(vim.inspect(value)))
end

---@param value any
---@param label string
function M.nil_(value, label)
  record(label, value == nil, ('expected nil, got %s'):format(vim.inspect(value)))
end

--- Print the summary and exit with a status the shell can act on.
function M.done()
  io.write(('  %d/%d passed\n'):format(total - failures, total))
  os.exit(failures == 0 and 0 or 1)
end

return M
```

- [ ] **Step 2: Write the runner**

Create `test/run.sh`:

```bash
#!/usr/bin/env bash
# Run every spec under test/spec with the real config loaded.
#
#   ./test/run.sh              # all specs
#   ./test/run.sh work         # only specs matching "work"
#
# Stubs are put first on PATH so specs never touch the real `linear` or GitHub.
# test/stub/gh is inert unless a GH_STUB_* variable is set, so specs that want
# real git behavior still get it.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

export PATH="$PWD/test/stub:$PATH"

filter="${1:-}"
status=0

for spec in test/spec/*_spec.lua; do
  [ -e "$spec" ] || continue
  if [ -n "$filter" ] && [[ "$spec" != *"$filter"* ]]; then continue; fi

  echo "$(basename "$spec")"
  if ! nvim -l "$spec"; then status=1; fi
done

if [ "$status" -eq 0 ]; then echo "all specs passed"; else echo "SPEC FAILURES"; fi
exit "$status"
```

- [ ] **Step 3: Write a spec proving the harness works**

Create `test/spec/parse_identifier_spec.lua`. This pins behavior that already
exists, so it must pass immediately — that is the point: it proves the harness
reports correctly rather than silently passing on everything.

```lua
local T = require 'test.helpers'
local work = require 'custom.work'

T.eq(work.parse_identifier '[ENG-245] do some engineering work', 'ENG-245', 'bracketed identifier')
T.eq(work.parse_identifier '[DATA-441] pipeline fix', 'DATA-441', 'non-ENG team key')
T.eq(work.parse_identifier '[abc-12] lowercase', 'ABC-12', 'lowercase normalized up')
T.eq(work.parse_identifier 'ENG-77 no brackets', 'ENG-77', 'unbracketed identifier')
T.eq(work.parse_identifier '[X2-9] digit in key', 'X2-9', 'digit in team key')
T.nil_(work.parse_identifier 'no ticket here', 'no identifier present')
T.nil_(work.parse_identifier '', 'empty string')
T.nil_(work.parse_identifier(nil), 'nil input')

T.done()
```

- [ ] **Step 4: Make it executable and run it**

```bash
chmod +x test/run.sh && ./test/run.sh
```

Expected: `parse_identifier_spec.lua` with 8 `ok` lines, `8/8 passed`, `all specs passed`, exit 0.

- [ ] **Step 5: Verify the harness actually fails**

Temporarily append `T.eq(1, 2, 'deliberate failure')` above `T.done()`, run
`./test/run.sh`, confirm it prints `FAIL deliberate failure -> expected 2, got 1`
and exits non-zero (`echo $?` → 1). Then remove that line and re-run to confirm green.

A harness that cannot fail is worse than no harness.

- [ ] **Step 6: Commit**

```bash
git add test/helpers.lua test/run.sh test/spec/parse_identifier_spec.lua
git commit -m "test: add headless spec harness

nvim -l loads the real config and propagates exit codes, so specs exercise
modules as they behave in a live session with no extra test dependency."
```

---

### Task 2: Path-aware git primitives

`custom.git` runs every command in Neovim's cwd. From `~/repos` that fails for
everything. Add an optional directory and a remote parser.

**Files:**
- Modify: `lua/custom/git.lua`
- Create: `test/spec/git_spec.lua`

**Interfaces:**
- Consumes: `test.helpers`.
- Produces:
  - `git.run(args: string[], dir?: string) -> string|nil`
  - `git.root(dir?: string) -> string|nil`
  - `git.branch(dir?: string) -> string|nil`
  - `git.cache_key(dir?: string) -> string|nil`
  - `git.remote(dir?: string) -> owner: string|nil, name: string|nil`

  `dir` is optional everywhere, so existing callers keep working unchanged.

- [ ] **Step 1: Write the failing test**

Create `test/spec/git_spec.lua`:

```lua
local T = require 'test.helpers'
local git = require 'custom.git'

local this_repo = vim.fn.fnamemodify(vim.fn.getcwd(), ':p'):gsub('/$', '')

-- Path-aware lookups work regardless of cwd.
vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.fnamemodify(this_repo, ':h')))
T.nil_(git.root(), 'root() is nil from the parent directory')
T.eq(git.root(this_repo), this_repo, 'root(dir) resolves from the parent directory')
T.ok(git.branch(this_repo), 'branch(dir) resolves from the parent directory')
T.ok(git.cache_key(this_repo), 'cache_key(dir) resolves from the parent directory')

local owner, name = git.remote(this_repo)
T.eq(owner, 'chanceygardener', 'remote owner parsed')
T.eq(name, 'kickstart.nvim', 'remote name parsed')

T.nil_(git.root '/tmp', 'root() nil outside any repo')

T.done()
```

- [ ] **Step 2: Run it to verify it fails**

```bash
./test/run.sh git
```

Expected: FAIL on `root(dir) resolves from the parent directory` (current `root()`
takes no argument, so the argument is ignored and it returns nil), and FAIL on both
`remote` assertions with `attempt to call field 'remote' (a nil value)`.

- [ ] **Step 3: Implement**

Replace the body of `lua/custom/git.lua` below the header comment:

```lua
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
```

- [ ] **Step 4: Run tests**

```bash
./test/run.sh
```

Expected: both specs pass. `parse_identifier_spec` must still be green — `git.lua`'s
existing callers pass no `dir` and must be unaffected.

- [ ] **Step 5: Verify the existing review workflow still works**

```bash
nvim --headless -c 'lua print(require("custom.review").resolve_base())' -c 'qa!' 2>&1 | grep -v treesitter
```

Expected: `origin/master`.

- [ ] **Step 6: Commit**

```bash
git add lua/custom/git.lua test/spec/git_spec.lua
git commit -m "feat(git): accept an optional directory for all lookups

Neovim is launched from the parent directory holding several checkouts, where
cwd-relative git resolution finds no repository. Also adds remote owner/name
parsing, used to scope a cross-repo PR search without configuration."
```

---

### Task 3: Buffer → repo identity

**Files:**
- Create: `lua/custom/repo.lua`
- Create: `test/spec/repo_spec.lua`

**Interfaces:**
- Consumes: `git.root`, `git.branch`, `git.remote` from Task 2.
- Produces:
  - `repo.for_path(path: string) -> Repo|nil`
  - `repo.for_buf(bufnr?: integer) -> Repo|nil`
  - `repo.invalidate()`
  - `Repo = { root: string, name: string, owner: string|nil, branch: string|nil }`

- [ ] **Step 1: Write the failing test**

Create `test/spec/repo_spec.lua`:

```lua
local T = require 'test.helpers'
local repo = require 'custom.repo'

local this_repo = vim.fn.fnamemodify(vim.fn.getcwd(), ':p'):gsub('/$', '')

-- Resolve from a file inside the repo, with cwd set to the parent.
vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.fnamemodify(this_repo, ':h')))
vim.cmd('edit ' .. vim.fn.fnameescape(this_repo .. '/init.lua'))

local r = repo.for_buf(0)
T.ok(r, 'resolves a repo from the buffer path')
T.eq(r and r.root, this_repo, 'root matches')
T.eq(r and r.name, 'kickstart.nvim', 'name matches')
T.eq(r and r.owner, 'chanceygardener', 'owner matches')
T.ok(r and r.branch, 'branch present')

T.nil_(repo.for_path '/tmp', 'nil outside any repo')

-- A buffer with no file falls back to cwd, which here is not a repo.
vim.cmd 'enew'
T.nil_(repo.for_buf(0), 'nil for a fileless buffer when cwd is not a repo')

T.done()
```

- [ ] **Step 2: Run it to verify it fails**

```bash
./test/run.sh repo
```

Expected: FAIL — `module 'custom.repo' not found`.

- [ ] **Step 3: Implement**

Create `lua/custom/repo.lua`:

```lua
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

---@param path string
---@return Repo|nil
function M.for_path(path)
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ':h')
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

--- Drop the cache. Call after cloning or moving a checkout.
function M.invalidate()
  cache = {}
end

return M
```

- [ ] **Step 4: Run tests**

```bash
./test/run.sh
```

Expected: all three specs pass.

- [ ] **Step 5: Commit**

```bash
git add lua/custom/repo.lua test/spec/repo_spec.lua
git commit -m "feat(repo): resolve repository identity from the buffer path

cwd says nothing about what you are editing when Neovim is launched from the
directory holding every checkout."
```

---

### Task 4: `gh search prs` stub

Cross-repo discovery needs a deterministic fixture before the implementation.

**Files:**
- Modify: `test/stub/gh`
- Modify: `test/README.md`

**Interfaces:**
- Produces: `gh search prs …` returning a payload spanning repos and tickets when
  `GH_STUB_SEARCH=1`; passes through to real `gh` otherwise.

- [ ] **Step 1: Extend the stub**

In `test/stub/gh`, after the existing `is_pr_view_json` block, add search handling.
Insert immediately before the final passthrough check:

```bash
# --- gh search prs ---------------------------------------------------------
if [ "${1:-}" = "search" ] && [ "${2:-}" = "prs" ] && [ "${GH_STUB_SEARCH:-}" = "1" ]; then
  if [ -n "${GH_STUB_ARGV:-}" ]; then printf '%s\n' "$*" >>"$GH_STUB_ARGV"; fi

  # Three PRs for ENG-1934 across two repos (one is a two-PR stack), plus an
  # unrelated ticket so grouping has something to separate. kg-assistant is
  # deliberately absent from disk to exercise the not-cloned path.
  cat <<'JSON'
[
  { "number": 12, "title": "[ENG-1934] Retry failed ingestion requests",
    "url": "https://github.com/acme/kgrisk/pull/12",
    "repository": { "name": "kgrisk", "nameWithOwner": "acme/kgrisk" } },
  { "number": 13, "title": "[ENG-1934] Retry ingestion: follow-up",
    "url": "https://github.com/acme/kgrisk/pull/13",
    "repository": { "name": "kgrisk", "nameWithOwner": "acme/kgrisk" } },
  { "number": 47, "title": "[ENG-1934] Backoff helper for the loader",
    "url": "https://github.com/acme/kgloader/pull/47",
    "repository": { "name": "kgloader", "nameWithOwner": "acme/kgloader" } },
  { "number": 8, "title": "[ENG-1934] Surface retry state",
    "url": "https://github.com/acme/kg-assistant/pull/8",
    "repository": { "name": "kg-assistant", "nameWithOwner": "acme/kg-assistant" } },
  { "number": 91, "title": "[DATA-441] Duplicate rows after worker restart",
    "url": "https://github.com/acme/kgloader/pull/91",
    "repository": { "name": "kgloader", "nameWithOwner": "acme/kgloader" } }
]
JSON
  exit 0
fi
```

- [ ] **Step 2: Verify the stub directly**

Two things to confirm: the fixture is returned when activated, and the stub stays
out of the way when it is not.

```bash
# activated -> fixture
GH_STUB_SEARCH=1 PATH="$PWD/test/stub:$PATH" \
  gh search prs '[ENG-1934]' --owner acme --json number,title,url,repository | head -5

# not activated -> real gh
PATH="$PWD/test/stub:$PATH" gh search prs --help 2>&1 | head -2
```

Expected: the JSON array from the first command; real `gh` help text from the
second. The stub intercepts only when `GH_STUB_SEARCH=1` **and** argv begins
`search prs`, so an inert stub directory on `PATH` cannot affect other specs.

- [ ] **Step 3: Document it**

Add to the `## gh` table in `test/README.md`:

```markdown
| `GH_STUB_SEARCH=1` | `search prs` returns a fixed multi-repo, multi-ticket payload |
| `GH_STUB_ARGV=<path>` | append each intercepted invocation's argv, for assertions |
```

And a line under it:

```markdown
The search fixture contains a two-PR stack in one repo, a second repo, a repo that
is deliberately absent from disk, and an unrelated ticket — so grouping, stacking,
and the not-cloned path are all exercised.
```

- [ ] **Step 4: Commit**

```bash
git add test/stub/gh test/README.md
git commit -m "test: add gh search prs fixture for cross-repo discovery"
```

---

### Task 5: Story discovery

**Files:**
- Modify: `lua/custom/work.lua`
- Create: `test/spec/discover_spec.lua`

**Interfaces:**
- Consumes: `repo.for_buf` (Task 3), `git.remote` (Task 2).
- Produces:
  - `work.discover(issue: string, owner: string, cb: fun(prs: Pr[]))`
  - `Pr = { repo: string, owner: string, number: integer, title: string, url: string, base: string|nil, root: string|nil }`
  - `work.group_by_issue(rows: table[]) -> table<string, Pr[]>` (pure; used by the switcher in Task 8)

  `base` is nil until filled in by Task 6; `root` is nil when the repo is not
  cloned beside the current one.

- [ ] **Step 1: Write the failing test**

Create `test/spec/discover_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
./test/run.sh discover
```

Expected: FAIL — `attempt to call field 'group_by_issue' (a nil value)`.

- [ ] **Step 3: Implement**

Add to `lua/custom/work.lua`, after `M.parse_identifier`:

```lua
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
```

- [ ] **Step 4: Run tests**

```bash
./test/run.sh
```

Expected: all four specs pass.

- [ ] **Step 5: Commit**

```bash
git add lua/custom/work.lua test/spec/discover_spec.lua
git commit -m "feat(work): discover a story's PRs across repos

One gh search scoped to the owner derived from the current remote. PRs group by
the ticket in their titles, so a stack collapses into one story, and sibling
checkouts are matched by remote rather than directory name."
```

---

### Task 6: Sticky ticket and active PR

The core restructure. Replaces per-repo context with a sticky story.

**Files:**
- Modify: `lua/custom/work.lua`
- Create: `test/spec/work_spec.lua`

**Interfaces:**
- Consumes: `M.discover`, `M.group_by_issue` (Task 5); `repo.for_buf` (Task 3).
- Produces:
  - `work.set_issue(issue: string, cb?: fun(ctx: Context|nil))` — sticky switch
  - `work.context() -> Context|nil` — resolving accessor
  - `work.get() -> Context|nil` — retained alias for `context()`, existing callers
  - `work.peek() -> Context|nil` — cache-only, zero subprocesses
  - `work.active() -> Pr|nil` — the story's PR for the current buffer's repo
  - `work.statusline() -> string`
  - `Context = { issue, title, prs: Pr[], searched_at: integer }`

  Note `active` is a **function**, not a field, because it depends on the current
  buffer and must never be stale.

- [ ] **Step 1: Write the failing test**

Create `test/spec/work_spec.lua`:

```lua
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

-- peek() and statusline() must never spawn a process.
local count = 0
local real = vim.system
vim.system = function(...)
  count = count + 1
  return real(...)
end
for _ = 1, 50 do
  work.peek()
  work.statusline()
end
vim.system = real
T.eq(count, 0, 'peek/statusline spawn zero processes')

T.done()
```

- [ ] **Step 2: Run it to verify it fails**

```bash
./test/run.sh work_spec
```

Expected: FAIL — `attempt to call field 'set_issue' (a nil value)`.

- [ ] **Step 3: Implement**

In `lua/custom/work.lua`, replace the module-local state block (`contexts`, `last`,
`resolving`) with:

```lua
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
```

Then replace `M.get`, `M.peek`, `M.statusline` and add the new functions:

```lua
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
```

Add `M.issue_for_repo`, which is the old per-repo resolution narrowed to one job:

```lua
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
```

Finally, fill in `base` for the active repo's PR lazily in `M.active()` — the search
does not return base branches. Add just before the `return pr` inside the loop:

```lua
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
```

- [ ] **Step 4: Run tests**

```bash
./test/run.sh
```

Expected: all five specs pass, including `peek/statusline spawn zero processes`.

- [ ] **Step 5: Update `M.show`, `M.refresh` and `M.setup` for the new shape**

`M.show` currently prints a single-repo context. Replace its body:

```lua
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
```

In `M.setup`, the `VimEnter` and branch-change handlers should call `M.context()`
rather than the removed `M.resolve`, and the branch comparison should use
`require('custom.repo').for_buf(0)`:

```lua
  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    callback = function()
      vim.defer_fn(function()
        pcall(M.context)
      end, 200)
    end,
  })

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
```

Also add the `:WorkSwitch` command to `M.setup`:

```lua
  vim.api.nvim_create_user_command('WorkSwitch', function(cmd)
    if cmd.args ~= '' then
      M.set_issue(cmd.args, function()
        M.show()
      end)
    else
      M.switch()
    end
  end, { nargs = '?', desc = 'Switch the current story' })
```

- [ ] **Step 6: Wire the statusline to `work.statusline()`**

`init.lua:1021-1043` currently builds the segment inline and reads `work.pr`, a
top-level field this task removes. Left alone it would silently drop the PR number.
It also duplicates the logic `M.statusline()` now owns. Replace the body of the
`section_git` override (keeping the surrounding comment and the `section_git` local)
so it reads:

```lua
      local section_git = statusline.section_git
      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_git = function(args)
        local git = section_git(args)
        local label = require('custom.work').statusline()
        if label == '' then
          return git
        end

        label = (vim.g.have_nerd_font and ' ' or '') .. label
        return git ~= '' and (git .. ' ' .. label) or label
      end
```

Verify it renders:

```bash
nvim --headless -c 'lua print(string.format("%q", require("mini.statusline").section_git({ trunc_width = 0 }) or ""))' -c 'qa!' 2>&1 | grep -v treesitter
```

Expected: a string — empty-ish when no story is resolved, containing the ticket
once one is. It must not error, and must not contain `nil`.

- [ ] **Step 7: Run everything and check startup**

```bash
./test/run.sh
nvim --headless -c 'qa!' 2>&1 | grep -v treesitter
nvim --headless --startuptime /tmp/st.log -c 'qa!' >/dev/null 2>&1 && grep STARTED /tmp/st.log
```

Expected: specs pass; startup silent; startup time within ~5ms of 47ms.

- [ ] **Step 8: Commit**

```bash
git add lua/custom/work.lua init.lua test/spec/work_spec.lua
git commit -m "feat(work): anchor context on the ticket, not the repo

A story is a sticky ticket plus every open PR implementing it across repos.
active() picks the PR for the buffer's repo and is recomputed per call, so a
diff can never point at the wrong repo. Contexts cache per ticket, making a
switch back instant."
```

---

### Task 7: Diffs across repos

**Files:**
- Modify: `lua/custom/review.lua`
- Create: `test/spec/review_spec.lua`

**Interfaces:**
- Consumes: `work.active()` (Task 6).
- Produces: `review.diff_command(pathspec?) -> string|nil` — extracted so the
  command string is assertable without opening a tab.

- [ ] **Step 1: Write the failing test**

Create `test/spec/review_spec.lua`:

```lua
local T = require 'test.helpers'
local review = require 'custom.review'
local work = require 'custom.work'

vim.env.GH_STUB_SEARCH = '1'

-- With no story, the command still works off the repo's own base.
vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.getcwd() .. '/init.lua'))
local cmd = review.diff_command()
T.ok(cmd, 'builds a command for the current repo')
T.ok(cmd and cmd:match '%-C', 'command carries -C so it works from a parent cwd')
T.ok(cmd and cmd:match '%.%.%.HEAD', 'three-dot range')

-- Pathspec is appended after a separator.
local filtered = review.diff_command 'lua/'
T.ok(filtered and filtered:match '%-%- lua/$', 'pathspec appended')

T.done()
```

- [ ] **Step 2: Run it to verify it fails**

```bash
./test/run.sh review_spec
```

Expected: FAIL — `attempt to call field 'diff_command' (a nil value)`.

- [ ] **Step 3: Implement**

In `lua/custom/review.lua`, replace `pr_base` and `M.open_diff`:

```lua
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
```

`M.resolve_base` needs its `cache_key()` calls to pass the buffer's repo root.
Replace each bare `cache_key()` in the file with:

```lua
local function key_for_buf()
  local r = require('custom.repo').for_buf(0)
  return r and git_util.cache_key(r.root) or nil
end
```

and call `key_for_buf()` in `M.resolve_base`, `M.set_base`, `M.clear_base` and
`M.current`. Likewise `M.git_status_tree` should pass `r.root`:

```lua
  vim.cmd(('Neotree left git_status git_base=%s dir=%s'):format(base, r.root))
```

- [ ] **Step 4: Run tests**

```bash
./test/run.sh
```

Expected: all six specs pass.

- [ ] **Step 5: Verify from the parent directory**

```bash
cd .. && nvim --headless repos/kickstart.nvim/init.lua \
  -c 'lua print(require("custom.review").diff_command())' -c 'qa!' 2>&1 | grep -v treesitter
cd - >/dev/null
```

Expected: a command containing `-C/Users/.../repos/kickstart.nvim` and `...HEAD`.
This is the whole point of the change — confirm it before moving on.

- [ ] **Step 6: Commit**

```bash
git add lua/custom/review.lua test/spec/review_spec.lua
git commit -m "feat(review): diff any repo from the parent directory

Diffview's -C{path} lets a diff target the buffer's repo without changing
directory, and the base now comes from the story's PR for that repo."
```

---

### Task 8: Story switcher

**Files:**
- Modify: `lua/custom/work.lua`
- Modify: `init.lua`
- Create: `test/spec/switcher_spec.lua`

**Interfaces:**
- Consumes: `M.group_by_issue` (Task 5), `M.set_issue` (Task 6).
- Produces:
  - `work.stories(cb: fun(items: StoryItem[]))` — merged, deduped, sorted
  - `work.switch()` — the picker
  - `StoryItem = { issue, title, count, source: 'mine'|'review'|'recent', current: boolean }`

- [ ] **Step 1: Write the failing test**

Create `test/spec/switcher_spec.lua`:

```lua
local T = require 'test.helpers'
local work = require 'custom.work'

vim.env.GH_STUB_SEARCH = '1'

local items
work.stories(function(result)
  items = result
end)
vim.wait(5000, function()
  return items ~= nil
end)

T.ok(items, 'stories returned')
T.ok(#items >= 2, 'at least two stories from the fixture')

local by_issue = {}
for _, it in ipairs(items) do
  by_issue[it.issue] = it
end

T.ok(by_issue['ENG-1934'], 'ENG-1934 present')
T.eq(by_issue['ENG-1934'].count, 4, 'PR stack counted as one story with 4 PRs')
T.ok(by_issue['DATA-441'], 'DATA-441 present')
T.eq(by_issue['DATA-441'].count, 1, 'single-PR story')

-- No duplicate rows for the same ticket.
local seen, dupes = {}, 0
for _, it in ipairs(items) do
  if seen[it.issue] then
    dupes = dupes + 1
  end
  seen[it.issue] = true
end
T.eq(dupes, 0, 'each ticket appears once')

T.done()
```

- [ ] **Step 2: Run it to verify it fails**

```bash
./test/run.sh switcher
```

Expected: FAIL — `attempt to call field 'stories' (a nil value)`.

- [ ] **Step 3: Implement**

Add to `lua/custom/work.lua`:

```lua
--- Run one `gh search prs` query, returning raw rows.
---@param args string[]
---@param cb fun(rows: table[])
local function search(args, cb)
  if vim.fn.executable 'gh' == 0 then
    return cb {}
  end

  local cmd = { 'gh', 'search', 'prs', '--state', 'open', '--json', 'number,title,url,repository' }
  vim.list_extend(cmd, args)

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
```

Note `item.text` is needed for snacks filtering — add it inside both `add()` and the
recent loop when building each item:

```lua
            text = issue .. ' ' .. (prs[1].title or ''),
```

and for the recent branch:

```lua
          text = issue .. ' ' .. (ctx.title or ''),
```

- [ ] **Step 4: Add the keymaps**

In `init.lua`, in the `stylua: ignore` block with the other `<leader>l` maps, add:

```lua
vim.keymap.set('n', '<leader>lw', function() require('custom.work').switch() end, { desc = '[L]inear: s[w]itch story' })
```

and change the existing `<leader>lc` line to call `show`, which it already does —
verify it reads:

```lua
vim.keymap.set('n', '<leader>lc', function() require('custom.work').show() end, { desc = '[L]inear: work [c]ontext' })
```

- [ ] **Step 5: Run tests and verify the keymap**

```bash
./test/run.sh
nvim --headless -c 'lua local n={} for _,m in ipairs(vim.api.nvim_get_keymap("n")) do n[m.lhs]=true end print("lw:", n[" lw"] and "ok" or "MISSING")' -c 'qa!' 2>&1 | grep -v treesitter
```

Expected: all seven specs pass; `lw: ok`.

- [ ] **Step 6: Commit**

```bash
git add lua/custom/work.lua init.lua test/spec/switcher_spec.lua
git commit -m "feat(work): add a story switcher

Rows are tickets rather than PRs, so a stack collapses into one entry. Merged
from your PRs, review requests, and stories visited this session."
```

---

### Task 9: Documentation

**Files:**
- Modify: `CHEATSHEET.md`
- Modify: `README.md`
- Modify: `test/README.md`

Done last, after the keymaps are confirmed interactively, so the docs describe what
actually happens.

- [ ] **Step 1: Rewrite the Linear cheatsheet section**

In `CHEATSHEET.md`, in `## Linear (linear-cli)`, replace the keybinding table with:

```markdown
| Keybinding / Command | Action |
|----------------------|--------|
| `Space lw` | Switch story — picker of your PRs, review requests, and recents |
| `Space lc` | Show the current story and all its PRs |
| `Space lt` | View the current story's Linear ticket |
| `Space lv` | View any issue — prompts for an identifier |
| `Space ls` | Search issues across **all teams** |
| `Space lS` | Search scoped to this repo's configured team |
| `Space lo` | Open the current ticket in the browser |
| `Space lr` | Re-search the current story |
| `:WorkSwitch ENG-1934` | Switch directly when you know the ticket |
```

Then replace the `### How the current ticket is resolved` section with:

```markdown
### Stories span repos

Work happens across several repos with no monorepo, so context is anchored on the
**ticket**, not the repo. A story is a Linear ticket plus every open PR
implementing it — including a stack of several PRs in one repo, which shows up as
one story rather than several.

The ticket is **sticky**: it stays put as you move between buffers in different
repos, and only changes when you switch. `Space lc` shows the whole story and which
PR belongs to the repo you're currently in.

The statusline shows `ENG-1934 · #12` when you're inside one of the story's repos
and `ENG-1934 · 3 PRs` when you're not.

Diffs know which repo they belong to, so `Space dr` works even with Neovim launched
from the parent directory holding every checkout.

### Things worth knowing

- **Switching is by ticket** — `Space lw`, or `:WorkSwitch ENG-1934` when you know
  it. Switching back to a story you were on is instant; it stays cached.
- **PRs are the unit of discovery.** A repo where you've started work but haven't
  pushed a PR won't be listed in the story. You can still work there normally.
- **GitHub's search index lags a little.** A PR opened seconds ago may not appear
  yet; `Space lc` shows how long ago the search ran and `Space lr` re-runs it.
- **Repos not cloned locally** are listed and marked, rather than failing.
```

- [ ] **Step 2: Update the README layout block**

In `README.md`, in the `### Layout` code block, add after the `lua/custom/git.lua` line:

```
lua/custom/repo.lua         which repo a buffer belongs to (buffer-relative)
```

and replace the paragraph beginning "`work.lua` is the shared resolver" with:

```markdown
`work.lua` is the shared resolver, and it is anchored on the **ticket** rather than
a repo: a story is a Linear ticket plus every open PR implementing it, discovered
with one `gh search prs` scoped to the org derived from the current repo's remote.
`review.lua` takes its diff base from the story's PR for whichever repo the current
buffer is in. Because work spans several repos with no monorepo, nothing resolves
against Neovim's cwd — `repo.lua` answers "which repo is this buffer in" and every
git call is made against that path.

Run `./test/run.sh` to exercise all of it offline; see `test/README.md`.
```

- [ ] **Step 3: Document the runner**

At the top of `test/README.md`, before `## linear`, add:

```markdown
## Running the specs

```sh
./test/run.sh          # everything
./test/run.sh work     # only specs matching "work"
```

Specs live in `test/spec/*_spec.lua` and run under `nvim -l`, which loads the real
config — so they exercise the modules exactly as a live session does. The runner
puts `test/stub` first on `PATH` and exits non-zero if any spec fails.
```

- [ ] **Step 4: Verify the docs match reality**

```bash
./test/run.sh
nvim --headless -c 'lua
local n = {}
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do n[m.lhs] = true end
for _, k in ipairs({" lw"," lc"," lt"," lv"," ls"," lS"," lo"," lr"}) do
  if not n[k] then print("MISSING " .. k) end
end
print("keymap check done")
local c = vim.api.nvim_get_commands({})
for _, cmd in ipairs({"WorkSwitch","WorkContext","WorkContextRefresh","LinearView","LinearSearch","LinearCurrent"}) do
  if not c[cmd] then print("MISSING :" .. cmd) end
end
print("command check done")' -c 'qa!' 2>&1 | grep -v treesitter
```

Expected: no `MISSING` lines.

- [ ] **Step 5: Commit**

```bash
git add CHEATSHEET.md README.md test/README.md
git commit -m "docs: describe the ticket-anchored, multi-repo work context"
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: path-aware git → Task 2;
`custom.repo` → Task 3; ticket-anchored sticky state → Task 6; `gh search prs`
discovery with owner derivation and remote-verified sibling mapping → Task 5;
switching → Task 8; diffs via `-C<root>` → Task 7; statusline → Task 6; error cases
→ spread across 5–7; testing → Tasks 1 and 4; docs → Task 9.

**Type consistency.** `Pr` fields (`repo`, `owner`, `number`, `title`, `url`,
`base`, `root`) are produced in Task 5 and consumed unchanged in 6, 7 and 8.
`Repo` fields (`root`, `name`, `owner`, `branch`) are produced in Task 3 and
consumed in 5, 6 and 7. `work.active()` is a function everywhere, never a field.
`git.run/root/branch/cache_key` all take `dir` as the final optional argument.

**Known gap, accepted:** `M.context()` calls `vim.wait` to drive an async resolve
to completion, which blocks briefly on first use in a session. This matches the
existing `M.get()` behavior being replaced and is only reachable from keymaps and
commands, never from `peek()`, `statusline()` or `active()`.
