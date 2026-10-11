# show-me-nvim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any terminal coding agent (Claude Code, Codex, Cursor) illustrate an explanation in the user's running Neovim through decks of numbered, multi-pane views that the user opens at their own pace.

**Architecture:** A bash CLI (`show-me`, shipped in an Agent Skill) finds the right Neovim through a unix socket named after a hash of that Neovim's startup cwd. It calls `require('custom.show_me').rpc(args)` over `--remote-expr`. Neovim validates each request, stores decks as JSON in `stdpath('state')`, and draws views only when the user presses `<leader>vN`. Drawing happens in a dedicated tab, using one of four fixed layouts.

**Tech Stack:** Neovim 0.12 Lua (`vim.uv`, `vim.fn.serverstart`, extmarks, snacks.nvim picker), bash 3.2-compatible shell, the existing `test/run.sh` + `test/helpers.lua` spec harness (`nvim -l`), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-11-show-me-nvim-design.md`

## Global Constraints

- Must behave identically on macOS (bash 3.2.57, BSD userland) and Ubuntu (GNU userland).
- CLI: bash 3.2. No associative arrays, `${x,,}`, `mapfile`, `realpath`, `readlink -f`, or `sed -i`. Use `id -u` rather than relying on `$UID`.
- Hashing: `sha256sum`, falling back to `shasum -a 256`. Take the first 16 hex chars of the sha256 of the physical (symlink-resolved) directory path, with no trailing newline.
- Socket dir: `/tmp/show-me-<uid>`, mode 0700. The CLI refuses if another user owns it.
- Exactly four layouts: `single` (1 pane), `cols2` (2), `cols3` (3), `main-stack` (3–4).
- At most 9 views per deck. Keep the 10 most recent decks per scope.
- Datetimes are integer epoch milliseconds.
- RPC replies are exactly `ok:<payload>` or `error:<reason>`. CLI exit codes: 0 ok, 1 rejected, 2 usage, 3 no reachable Neovim.
- Nothing ever moves focus on arrival. Agents only cause a `vim.notify`.
- Lua style follows the existing `lua/custom/*.lua`: module docstring header, `---@` annotations, `local M = {}`, 2-space indent, single quotes. Don't run stylua across existing files (see memory); new files may be formatted with `stylua <newfile>`.
- `~/.config/nvim` is a symlink to this checkout, which is why `nvim -l` specs exercise the working tree. Execute in this checkout, not in a separate worktree.

## Review Focus

1. **The same file in both panes** of `cols2`, with different ranges (comparing two functions in one file). Both ranges must stay highlighted, and opening the second pane must not clear the first. Covered in Task 4.
2. **The file shrank** after the deck was made, so the range now runs past EOF. Opening the view must not raise; the cursor clamps to the last line. Covered in Task 4.
3. **Titles and paths containing `'`, `%`, and spaces** have to survive the shell → Vimscript string → Lua round trip, and the winbar must escape `%`. Covered in Task 6 (`it's 100%.py`) and Task 4.
4. **A stale socket file** left by a crashed Neovim. `listen` replaces it, and the CLI skips any socket that doesn't answer. A *live* socket owned by another Neovim must not be stolen. Covered in Task 1.
5. **Pressing `<leader>v1` before any deck exists**, or asking for a view number past the end. The user gets a notification and no error. Covered in Task 6 (via RPC into the child Neovim).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `lua/custom/show_me/socket.lua` | create | Socket dir/path/hash derivation; `listen(scope)` with live/stale probing |
| `lua/custom/show_me/layout.lua` | create | `PANES`, `NAMES`, `build(name, count)` |
| `lua/custom/show_me/deck.lua` | create | `ShowMeRejection`, `parse_pane`, `view`, `ShowMeStore` (JSON persistence) |
| `lua/custom/show_me/render.lua` | create | Dedicated tab, `open(deck, n)`, `step`, `close`, highlights, winbar |
| `lua/custom/show_me/init.lua` | create | `setup`, `rpc`, `current`, `open`, `pick`, `status` |
| `init.lua` | modify (~line 197 and ~line 408) | `setup()` call, keymaps, which-key group |
| `skills/show-me-nvim/scripts/show-me` | create | CLI |
| `skills/show-me-nvim/SKILL.md` | create | Agent instructions |
| `skills/show-me-nvim/install.sh` | create | Symlinks skill + CLI |
| `test/spec/show_me_socket_spec.lua` | create | Task 1 |
| `test/spec/show_me_layout_spec.lua` | create | Task 2 |
| `test/spec/show_me_deck_spec.lua` | create | Task 3 |
| `test/spec/show_me_render_spec.lua` | create | Task 4 |
| `test/spec/show_me_cli_spec.lua` | create | Task 6 (integration: real CLI ↔ child Neovim) |
| `.github/workflows/specs.yml` | create | macOS + Ubuntu matrix |
| `README.md`, `CHEATSHEET.md` | modify | Docs |

---

### Task 1: Socket derivation and listening

**Files:**
- Create: `lua/custom/show_me/socket.lua`
- Test: `test/spec/show_me_socket_spec.lua`

**Interfaces:**
- Produces:
  - `socket.dir() -> string`
  - `socket.hash(scope: string) -> string` (16 hex chars)
  - `socket.path(scope: string) -> string`
  - `socket.listen(scope: string) -> (address: string|nil, reason: string|nil)`

- [ ] **Step 1: Write the failing test**

`test/spec/show_me_socket_spec.lua`:

```lua
local T = require 'test.helpers'
local socket = require 'custom.show_me.socket'

-- Derivation must match the CLI byte for byte: sha256 of the physical path.
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
local real = vim.uv.fs_realpath(tmp)
T.eq(socket.hash(tmp), vim.fn.sha256(real):sub(1, 16), 'hash uses the resolved path')
T.eq(#socket.hash(tmp), 16, 'hash is 16 hex chars')
T.eq(socket.path(tmp), ('/tmp/show-me-%d/%s.sock'):format(vim.uv.getuid(), socket.hash(tmp)), 'path layout')

-- A stale file at the socket path (crashed Neovim) is replaced.
local stale_scope = tmp .. '/stale'
vim.fn.mkdir(stale_scope, 'p')
vim.fn.mkdir(socket.dir(), 'p')
vim.fn.writefile({}, socket.path(stale_scope))
local addr, reason = socket.listen(stale_scope)
T.eq(addr, socket.path(stale_scope), 'stale socket file replaced by a live server')
T.nil_(reason, 'no reason when listening')
T.eq(vim.uv.fs_stat(socket.dir()).mode % 512, tonumber('700', 8), 'socket dir is private')
vim.fn.serverstop(addr)

-- A live socket owned by another Neovim is left alone.
local live_scope = tmp .. '/live'
vim.fn.mkdir(live_scope, 'p')
local other = vim.system { 'nvim', '--headless', '--clean', '--listen', socket.path(live_scope) }
vim.wait(5000, function() return vim.uv.fs_stat(socket.path(live_scope)) ~= nil end, 50)
addr, reason = socket.listen(live_scope)
T.nil_(addr, 'does not steal a live socket')
T.ok(reason and reason:find('another Neovim', 1, true), 'explains why it did not listen')
other:kill(9)

T.done()
```

Note: the mode assertion only holds if `socket.dir()` was created by this code. If `/tmp/show-me-<uid>` already exists from a previous run, it was created by the same code, so the assertion still holds.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `./test/run.sh show_me_socket`
Expected: FAIL with `module 'custom.show_me.socket' not found`.

- [ ] **Step 3: Implement**

`lua/custom/show_me/socket.lua`:

```lua
--- The socket a Neovim listens on so `show-me` agents can find it.
---
--- Neovim and the `show-me` CLI derive the same path independently: a socket
--- named by a hash of a directory (the "scope"). Neovim registers its startup
--- cwd; the CLI walks up from the agent's checkout trying each ancestor. Keep
--- this derivation byte-for-byte in step with skills/show-me-nvim/scripts/show-me.

local M = {}

local DIR_MODE = tonumber('700', 8)

---@return string
function M.dir()
  return '/tmp/show-me-' .. vim.uv.getuid()
end

---@param scope string Directory; symlinks are resolved before hashing
---@return string
function M.hash(scope)
  return vim.fn.sha256(vim.uv.fs_realpath(scope) or scope):sub(1, 16)
end

---@param scope string
---@return string
function M.path(scope)
  return ('%s/%s.sock'):format(M.dir(), M.hash(scope))
end

---Whether a Neovim is answering on `path`.
---@param path string
---@return boolean
local function answers(path)
  local ok, chan = pcall(vim.fn.sockconnect, 'pipe', path, { rpc = true })
  if ok and chan > 0 then
    vim.fn.chanclose(chan)
    return true
  end
  return false
end

---Listen on the socket for `scope`, unless another live Neovim already owns it.
---@param scope string
---@return string|nil address
---@return string|nil reason Why nothing was started
function M.listen(scope)
  local dir = M.dir()
  vim.fn.mkdir(dir, 'p', DIR_MODE)
  local stat = vim.uv.fs_stat(dir)
  if not stat or stat.uid ~= vim.uv.getuid() then
    return nil, dir .. ' is not owned by you'
  end

  local path = M.path(scope)
  if vim.uv.fs_stat(path) then
    if answers(path) then
      return nil, 'another Neovim already serves ' .. scope
    end
    os.remove(path)
  end

  local ok, address = pcall(vim.fn.serverstart, path)
  if not ok then
    return nil, tostring(address)
  end
  return address
end

return M
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `./test/run.sh show_me_socket`
Expected: all `ok`, then `all specs passed`.

- [ ] **Step 5: Commit**

```bash
git add lua/custom/show_me/socket.lua test/spec/show_me_socket_spec.lua
git commit -m "feat(show-me): derive and claim the per-scope socket"
```

---

### Task 2: Layouts

**Files:**
- Create: `lua/custom/show_me/layout.lua`
- Test: `test/spec/show_me_layout_spec.lua`

**Interfaces:**
- Produces:
  - `layout.PANES: table<string, {integer, integer}>` (min, max)
  - `layout.NAMES: string[]` = `{ 'single', 'cols2', 'cols3', 'main-stack' }`
  - `layout.build(name: string, count: integer) -> integer[]`: splits the current window, which must be the tab's only window, and returns window ids in pane order

- [ ] **Step 1: Write the failing test**

`test/spec/show_me_layout_spec.lua`:

```lua
local T = require 'test.helpers'
local layout = require 'custom.show_me.layout'

---Build `name` in a fresh tab.
---@return integer[] wins
---@return table tree `winlayout()` of the tab
local function build(name, count)
  vim.cmd 'tabnew'
  local wins = layout.build(name, count)
  return wins, vim.fn.winlayout()
end

T.eq(#layout.NAMES, 4, 'exactly four approved layouts')

local wins, tree = build('single', 1)
T.eq(#wins, 1, 'single: one window')
T.eq(tree[1], 'leaf', 'single: one leaf')

wins, tree = build('cols3', 3)
T.eq(tree[1], 'row', 'cols3: a row')
T.eq(#tree[2], 3, 'cols3: three columns')
for i = 1, 3 do
  T.eq(tree[2][i][2], wins[i], ('cols3: pane %d is column %d'):format(i, i))
end

wins, tree = build('main-stack', 4)
T.eq(tree[1], 'row', 'main-stack: a row')
T.eq(tree[2][1][2], wins[1], 'main-stack: pane 1 is the left column')
T.eq(tree[2][2][1], 'col', 'main-stack: right side is a column')
T.eq(#tree[2][2][2], 3, 'main-stack: three stacked panes')
for i = 2, 4 do
  T.eq(tree[2][2][2][i - 1][2], wins[i], ('main-stack: pane %d is stack row %d'):format(i, i - 1))
end
T.ok(vim.api.nvim_win_get_width(wins[1]) > vim.api.nvim_win_get_width(wins[2]), 'main-stack: main pane is wider')

-- Geometry must not depend on the user's split options.
vim.o.splitright, vim.o.splitbelow = false, false
wins, tree = build('cols2', 2)
T.eq(tree[2][1][2], wins[1], 'cols2: pane 1 stays left with splitright off')
wins, tree = build('main-stack', 3)
T.eq(tree[2][2][2][1][2], wins[2], 'main-stack: pane 2 stays on top with splitbelow off')

T.done()
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `./test/run.sh show_me_layout`
Expected: FAIL with `module 'custom.show_me.layout' not found`.

- [ ] **Step 3: Implement**

`lua/custom/show_me/layout.lua`:

```lua
--- The approved show-me layouts, and how to build each in the current tab.
---
--- Agents may only choose from these four: screen space is finite, and a fixed
--- menu keeps every view readable. Splits name their direction explicitly so the
--- user's 'splitright'/'splitbelow' never change the geometry.

local M = {}

--- Pane count each layout accepts, as { min, max }.
---@type table<string, integer[]>
M.PANES = { single = { 1, 1 }, cols2 = { 2, 2 }, cols3 = { 3, 3 }, ['main-stack'] = { 3, 4 } }

--- Layout names in the order they are documented.
M.NAMES = { 'single', 'cols2', 'cols3', 'main-stack' }

--- Share of the screen width the primary pane of `main-stack` takes.
local MAIN_SHARE = 0.6

---@param win integer
---@param direction 'right'|'below'
---@return integer
local function split(win, direction)
  return vim.api.nvim_open_win(0, false, { split = direction, win = win })
end

---@param count integer
---@return integer[]
local function columns(count)
  local wins = { vim.api.nvim_get_current_win() }
  for i = 2, count do
    wins[i] = split(wins[i - 1], 'right')
  end
  vim.cmd 'wincmd ='
  return wins
end

---@param count integer
---@return integer[]
local function main_stack(count)
  local main = vim.api.nvim_get_current_win()
  local wins = { main, split(main, 'right') }
  for i = 3, count do
    wins[i] = split(wins[i - 1], 'below')
  end
  vim.cmd 'wincmd ='
  vim.api.nvim_win_set_width(main, math.floor(vim.o.columns * MAIN_SHARE))
  return wins
end

local BUILDERS = { single = columns, cols2 = columns, cols3 = columns, ['main-stack'] = main_stack }

---Split the current window, which must be the tab's only one, into layout `name`.
---@param name string One of `M.NAMES`
---@param count integer Pane count, within `M.PANES[name]`
---@return integer[] wins Window ids in pane order
function M.build(name, count)
  return BUILDERS[name](count)
end

return M
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `./test/run.sh show_me_layout`
Expected: all `ok`.

- [ ] **Step 5: Commit**

```bash
git add lua/custom/show_me/layout.lua test/spec/show_me_layout_spec.lua
git commit -m "feat(show-me): add the four approved view layouts"
```

---

### Task 3: Decks — validation and persistence

**Files:**
- Create: `lua/custom/show_me/deck.lua`
- Test: `test/spec/show_me_deck_spec.lua`

**Interfaces:**
- Consumes: `layout.PANES`, `layout.NAMES` (Task 2)
- Produces:
  - `deck.MAX_VIEWS = 9`, `deck.KEEP = 10`
  - `deck.reject(fmt: string, ...)`: raises a `ShowMeRejection`
  - `deck.is_rejection(err: any) -> boolean`
  - `deck.parse_pane(spec: string) -> ShowMePane` (`{ path, first?, last? }`)
  - `deck.view(layout_name: string, specs: string[], title: string|nil) -> ShowMeView`
  - `deck.store(root: string) -> ShowMeStore`, with methods:
    - `:ids() -> integer[]` (ascending)
    - `:load(id) -> ShowMeDeck|nil`
    - `:get(id: string|integer) -> ShowMeDeck` (rejects if unknown)
    - `:create(title: string|nil) -> ShowMeDeck`
    - `:add_view(id, view: ShowMeView) -> integer`
    - `:finish(id) -> ShowMeDeck`
    - `:list_done() -> ShowMeDeck[]` (newest first)
    - `:latest_done() -> ShowMeDeck|nil`

- [ ] **Step 1: Write the failing test**

`test/spec/show_me_deck_spec.lua`:

```lua
local T = require 'test.helpers'
local deck = require 'custom.show_me.deck'

local fixture = vim.fn.tempname() .. '.txt'
vim.fn.writefile({ 'a', 'b', 'c', 'd', 'e' }, fixture)

---Run `fn` and return its rejection reason, or nil if it succeeded.
---@return string|nil
local function rejection(fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then
    return nil
  end
  return deck.is_rejection(err) and tostring(err) or ('NOT A REJECTION: ' .. tostring(err))
end

---@param reason string|nil
---@param needle string
---@param label string
local function rejects_with(reason, needle, label)
  T.ok(reason and reason:find(needle, 1, true), ('%s (got %s)'):format(label, tostring(reason)))
end

-- parse_pane
local p = deck.parse_pane(fixture .. ':2-4')
T.eq(p.path, fixture, 'pane path kept absolute')
T.eq(p.first, 2, 'range first')
T.eq(p.last, 4, 'range last')
p = deck.parse_pane(fixture .. ':3')
T.eq(p.first, 3, 'single line: first')
T.eq(p.last, 3, 'single line: last')
T.nil_(deck.parse_pane(fixture).first, 'whole file has no range')

rejects_with(rejection(deck.parse_pane, fixture .. ':4-2'), 'first > last', 'reversed range')
rejects_with(rejection(deck.parse_pane, fixture .. ':0-2'), 'line 1 or later', 'zero line')
rejects_with(rejection(deck.parse_pane, fixture .. ':4-9'), '(5 lines)', 'past EOF names line count')
rejects_with(rejection(deck.parse_pane, fixture .. ':1-2-3'), 'malformed range', 'malformed range')
rejects_with(rejection(deck.parse_pane, '/no/such/file.py'), 'no readable file', 'missing file')

-- view
local v = deck.view('cols2', { fixture .. ':1-2', fixture }, 'Compare')
T.eq(v.layout, 'cols2', 'view layout')
T.eq(#v.panes, 2, 'view panes')
T.eq(v.title, 'Compare', 'view title')
rejects_with(rejection(deck.view, 'grid', { fixture }), 'valid: single, cols2, cols3, main-stack', 'unknown layout lists layouts')
rejects_with(rejection(deck.view, 'cols2', { fixture }), 'cols2 takes 2 panes, got 1', 'pane count')
rejects_with(rejection(deck.view, 'main-stack', { fixture, fixture }), 'main-stack takes 3-4 panes, got 2', 'ranged pane count')

-- store
local root = vim.fn.tempname()
local store = deck.store(root)
rejects_with(rejection(store.create, store, '  '), 'needs a title', 'blank title')
local d = store:create 'First'
T.eq(d.id, 1, 'first deck is 1')
T.eq(type(d.created_at), 'number', 'created_at is a number')
T.ok(d.created_at > 1700000000000, 'created_at is epoch milliseconds')
T.eq(d.done, false, 'new deck is not done')

T.eq(store:add_view(1, v), 1, 'first view is 1')
T.eq(store:add_view('1', deck.view('single', { fixture })), 2, 'string ids accepted')
rejects_with(rejection(store.add_view, store, 99, v), 'unknown deck 99', 'unknown deck')
rejects_with(rejection(store.finish, store, store:create('Empty').id), 'has no views', 'empty deck cannot finish')

T.nil_(store:latest_done(), 'no done decks yet')
store:finish(1)
T.eq(store:latest_done().id, 1, 'finished deck is latest done')
rejects_with(rejection(store.add_view, store, 1, v), 'already done', 'done deck is closed')

local full = store:create 'Full'
for _ = 1, deck.MAX_VIEWS do
  store:add_view(full.id, v)
end
rejects_with(rejection(store.add_view, store, full.id, v), 'already has 9 views', 'view cap')

-- persistence round trip, from a fresh store on the same root
local loaded = deck.store(root):get(1)
T.eq(loaded.title, 'First', 'title persisted')
T.eq(loaded.views[1].panes[1].first, 1, 'pane range persisted')
T.eq(loaded.views[1].title, 'Compare', 'view title persisted')
T.eq(loaded.done, true, 'done flag persisted')

-- pruning keeps the newest KEEP decks and ids stay monotonic
for i = 1, 12 do
  store:create('Bulk ' .. i)
end
local ids = store:ids()
T.eq(#ids, deck.KEEP, 'only KEEP decks kept')
T.eq(store:create('Next').id, ids[#ids] + 1, 'ids keep increasing after pruning')

-- list_done is newest first
local a = store:create 'A'
store:add_view(a.id, v)
store:finish(a.id)
T.eq(store:list_done()[1].id, a.id, 'list_done newest first')

T.done()
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `./test/run.sh show_me_deck`
Expected: FAIL with `module 'custom.show_me.deck' not found`.

- [ ] **Step 3: Implement**

`lua/custom/show_me/deck.lua`:

```lua
--- show-me decks: an agent's illustrations for one explanation, as data.
---
--- A deck is a titled, numbered list of views; a view is one approved layout
--- filled with panes; a pane is a file with an optional highlighted line range.
--- This module validates what the CLI sends and persists decks as JSON, one
--- file per deck. It never touches windows; `render.lua` draws views.

local layout = require 'custom.show_me.layout'

local M = {}

--- `<leader>v1`–`<leader>v9` are the only view keys, so a deck holds at most 9.
M.MAX_VIEWS = 9

--- Decks kept on disk per scope; older ones are deleted on each `create`.
M.KEEP = 10

---@class ShowMePane
---@field path string Absolute path
---@field first? integer 1-based first highlighted line
---@field last? integer 1-based last highlighted line, inclusive

---@class ShowMeView
---@field layout string One of `layout.NAMES`
---@field title? string
---@field panes ShowMePane[]

---@class ShowMeDeck
---@field id integer Monotonic per scope
---@field title string
---@field created_at integer Epoch milliseconds
---@field done boolean Only done decks are announced and can become current
---@field views ShowMeView[]

--- A request the agent got wrong. Raised with `error()` so validation can bail
--- from any depth; `custom.show_me.rpc` turns it into the CLI's `error:` reply.
---@class ShowMeRejection
---@field reason string
local Rejection = {}
Rejection.__index = Rejection
Rejection.__tostring = function(self)
  return self.reason
end

---@param fmt string
---@param ... any
function M.reject(fmt, ...)
  error(setmetatable({ reason = fmt:format(...) }, Rejection), 0)
end

---@param err any
---@return boolean
function M.is_rejection(err)
  return getmetatable(err) == Rejection
end

---@return integer
local function now_ms()
  local sec, usec = vim.uv.gettimeofday()
  return sec * 1000 + math.floor(usec / 1000)
end

---Parse `path[:N[-M]]` into a pane, checking that the file and range exist.
---@param spec string
---@return ShowMePane
function M.parse_pane(spec)
  local path, range = spec:match '^(.+):([%d%-]+)$'
  path = vim.fn.fnamemodify(path or spec, ':p')
  if vim.fn.filereadable(path) ~= 1 then
    M.reject('no readable file at %s', path)
  end
  if not range then
    return { path = path }
  end

  local first, last = range:match '^(%d+)%-(%d+)$'
  first = first or range:match '^(%d+)$'
  if not first then
    M.reject('malformed range %q in %s (use N or N-M)', range, spec)
  end
  first, last = tonumber(first), tonumber(last or first)
  local lines = #vim.fn.readfile(path)
  if first < 1 then
    M.reject('range in %s must start at line 1 or later', path)
  elseif first > last then
    M.reject('range %d-%d in %s has first > last', first, last, path)
  elseif last > lines then
    M.reject('range %d-%d is past the end of %s (%d lines)', first, last, path, lines)
  end
  return { path = path, first = first, last = last }
end

---@param layout_name string
---@param specs string[] Pane specs, `path[:N[-M]]`
---@param title? string
---@return ShowMeView
function M.view(layout_name, specs, title)
  local counts = layout.PANES[layout_name]
  if not counts then
    M.reject('unknown layout %q (valid: %s)', tostring(layout_name), table.concat(layout.NAMES, ', '))
  end
  local min, max = counts[1], counts[2]
  if #specs < min or #specs > max then
    local accepted = min == max and tostring(min) or ('%d-%d'):format(min, max)
    M.reject('%s takes %s panes, got %d', layout_name, accepted, #specs)
  end
  return { layout = layout_name, title = title, panes = vim.tbl_map(M.parse_pane, specs) }
end

--- Decks for one scope, one JSON file each under `root`.
---@class ShowMeStore
---@field root string
local Store = {}
Store.__index = Store

---@param root string
---@return ShowMeStore
function M.store(root)
  vim.fn.mkdir(root, 'p')
  return setmetatable({ root = root }, Store)
end

---@param id integer
---@return string
function Store:file(id)
  return ('%s/%d.json'):format(self.root, id)
end

---@return integer[] ids Ascending
function Store:ids()
  local ids = {}
  for name in vim.fs.dir(self.root) do
    local id = name:match '^(%d+)%.json$'
    if id then
      ids[#ids + 1] = tonumber(id)
    end
  end
  table.sort(ids)
  return ids
end

---@param id integer
---@return ShowMeDeck|nil
function Store:load(id)
  local ok, lines = pcall(vim.fn.readfile, self:file(id))
  if not ok or #lines == 0 then
    return nil
  end
  return vim.json.decode(table.concat(lines, '\n'))
end

---@param d ShowMeDeck
function Store:save(d)
  vim.fn.writefile({ vim.json.encode(d) }, self:file(d.id))
end

---@param id string|integer
---@return ShowMeDeck
function Store:get(id)
  local d = tonumber(id) and self:load(tonumber(id))
  if not d then
    M.reject('unknown deck %s', tostring(id))
  end
  return d
end

---Start a new deck and prune the oldest beyond `M.KEEP`.
---@param title string|nil
---@return ShowMeDeck
function Store:create(title)
  if not title or vim.trim(title) == '' then
    M.reject 'a deck needs a title'
  end
  local ids = self:ids()
  local d = { id = (ids[#ids] or 0) + 1, title = title, created_at = now_ms(), done = false, views = {} }
  self:save(d)
  for i = 1, #ids + 1 - M.KEEP do
    os.remove(self:file(ids[i]))
  end
  return d
end

---@param id string|integer
---@param view ShowMeView
---@return integer n The view's number within the deck
function Store:add_view(id, view)
  local d = self:get(id)
  if d.done then
    M.reject('deck %d is already done; start a new one', d.id)
  elseif #d.views >= M.MAX_VIEWS then
    M.reject('deck %d already has %d views, the most <leader>v1-9 can reach', d.id, M.MAX_VIEWS)
  end
  table.insert(d.views, view)
  self:save(d)
  return #d.views
end

---@param id string|integer
---@return ShowMeDeck
function Store:finish(id)
  local d = self:get(id)
  if #d.views == 0 then
    M.reject('deck %d has no views', d.id)
  end
  d.done = true
  self:save(d)
  return d
end

---@return ShowMeDeck[] decks Newest first
function Store:list_done()
  local done = {}
  local ids = self:ids()
  for i = #ids, 1, -1 do
    local d = self:load(ids[i])
    if d and d.done then
      done[#done + 1] = d
    end
  end
  return done
end

---@return ShowMeDeck|nil
function Store:latest_done()
  return self:list_done()[1]
end

return M
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `./test/run.sh show_me_deck`
Expected: all `ok`.

- [ ] **Step 5: Commit**

```bash
git add lua/custom/show_me/deck.lua test/spec/show_me_deck_spec.lua
git commit -m "feat(show-me): validate and persist decks of views"
```

---

### Task 4: Rendering views

**Files:**
- Create: `lua/custom/show_me/render.lua`
- Test: `test/spec/show_me_render_spec.lua`

**Interfaces:**
- Consumes: `layout.build` (Task 2), `ShowMeDeck`/`ShowMePane` shapes (Task 3)
- Produces:
  - `render.NS: integer` (extmark namespace)
  - `render.tab() -> integer|nil`
  - `render.position() -> { deck: ShowMeDeck, view: integer }|nil`
  - `render.open(deck: ShowMeDeck, n: integer)`
  - `render.step(delta: integer)`: does nothing outside the show-me tab
  - `render.close()`
  - `render.clear()`
  - `render.on_tab_closed()`

- [ ] **Step 1: Write the failing test**

`test/spec/show_me_render_spec.lua`:

```lua
local T = require 'test.helpers'
local render = require 'custom.show_me.render'

local function numbered(n)
  return vim.tbl_map(tostring, vim.fn.range(1, n))
end

local a = vim.fn.tempname() .. '.lua'
local b = vim.fn.tempname() .. '.lua'
vim.fn.writefile(numbered(100), a)
vim.fn.writefile(numbered(20), b) -- the deck below claims lines 15-40: the file "shrank"

---@type ShowMeDeck
local d = {
  id = 1,
  title = 'Demo 100%',
  created_at = 0,
  done = true,
  views = {
    { layout = 'cols2', title = 'Same file', panes = { { path = a, first = 10, last = 12 }, { path = a, first = 50, last = 55 } } },
    { layout = 'single', panes = { { path = b, first = 15, last = 40 } } },
  },
}

local home = vim.api.nvim_get_current_tabpage()
render.open(d, 1)
local tab = render.tab()
T.ok(tab and tab ~= home, 'views open in their own tab')

local wins = vim.api.nvim_tabpage_list_wins(tab)
T.eq(#wins, 2, 'cols2 has two panes')
local buf = vim.api.nvim_win_get_buf(wins[1])
T.eq(vim.api.nvim_win_get_buf(wins[2]), buf, 'both panes show the same buffer')
T.eq(#vim.api.nvim_buf_get_extmarks(buf, render.NS, 0, -1, {}), 2, 'both ranges in a shared buffer stay highlighted')
T.eq(vim.api.nvim_win_get_cursor(wins[1])[1], 10, 'pane 1 cursor at its range')
T.eq(vim.api.nvim_win_get_cursor(wins[2])[1], 50, 'pane 2 cursor at its range')
T.ok(vim.wo[wins[1]].winbar:find('1/2', 1, true), 'winbar shows position')
T.ok(vim.wo[wins[1]].winbar:find('Same file', 1, true), 'winbar shows view title')
T.eq(vim.api.nvim_get_current_win(), wins[1], 'focus lands on pane 1')

render.step(1)
T.eq(render.position().view, 2, ']v moves to view 2')
wins = vim.api.nvim_tabpage_list_wins(render.tab())
T.eq(#wins, 1, 'single has one pane')
T.eq(vim.api.nvim_win_get_cursor(wins[1])[1], 20, 'range past EOF clamps to the last line')
T.ok(vim.wo[wins[1]].winbar:find('Demo 100%%', 1, true), 'falls back to deck title, with % escaped')

render.step(1)
T.eq(render.position().view, 2, ']v at the last view stays put')

vim.api.nvim_set_current_tabpage(home)
render.step(-1)
T.eq(render.position().view, 2, '[v does nothing outside the show-me tab')

render.open(d, 1)
local count = 0
for _, t in ipairs(vim.api.nvim_list_tabpages()) do
  count = count + (vim.t[t].show_me and 1 or 0)
end
T.eq(count, 1, 'reopening reuses the single show-me tab')

render.close()
T.nil_(render.tab(), 'close removes the show-me tab')
T.nil_(render.position(), 'close forgets the position')
T.eq(#vim.api.nvim_buf_get_extmarks(buf, render.NS, 0, -1, {}), 0, 'close clears highlights')

T.done()
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `./test/run.sh show_me_render`
Expected: FAIL with `module 'custom.show_me.render' not found`.

- [ ] **Step 3: Implement**

`lua/custom/show_me/render.lua`:

```lua
--- Draws show-me views in one dedicated tab, rebuilt from scratch per view.
---
--- Panes hold real file buffers, so LSP, `gd` and edits work as usual; ranges
--- are marked with the `ShowMeRange` highlight (linked to Visual by default) and
--- scrolled to the top of their pane. The user's own tabs are never touched.

local layout = require 'custom.show_me.layout'

local M = {}

M.NS = vim.api.nvim_create_namespace 'show_me'

---@class ShowMePosition
---@field deck ShowMeDeck
---@field view integer

---@type ShowMePosition|nil
local position

---@return integer|nil
function M.tab()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.t[tab].show_me then
      return tab
    end
  end
end

---@return ShowMePosition|nil
function M.position()
  return position
end

--- Switch to the show-me tab, reduced to one window, creating the tab if needed.
local function reset_tab()
  local tab = M.tab()
  if tab then
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd 'silent only!'
  else
    vim.cmd 'tabnew'
    vim.bo.bufhidden = 'wipe'
    vim.t.show_me = true
  end
end

---@param deck ShowMeDeck
---@param n integer
---@param pane ShowMePane
---@return string
local function winbar(deck, n, pane)
  local where = vim.fn.fnamemodify(pane.path, ':~:.')
  if pane.first then
    where = ('%s:%d-%d'):format(where, pane.first, pane.last)
  end
  local text = ('%d/%d · %s · %s'):format(n, #deck.views, deck.views[n].title or deck.title, where)
  return (text:gsub('%%', '%%%%'))
end

---Load `pane` into `win`, highlight its range and scroll it to the top.
---@param win integer
---@param pane ShowMePane
local function show_pane(win, pane)
  -- bufload, unlike :edit, never stops on a swap-file prompt.
  local buf = vim.fn.bufadd(pane.path)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  vim.api.nvim_win_set_buf(win, buf)
  if not pane.first then
    return
  end

  -- The file may have shrunk since the agent made the deck.
  local first = math.min(pane.first, vim.api.nvim_buf_line_count(buf))
  vim.api.nvim_buf_set_extmark(buf, M.NS, first - 1, 0, {
    end_row = pane.last,
    hl_group = 'ShowMeRange',
    hl_eol = true,
    strict = false,
  })
  vim.api.nvim_win_set_cursor(win, { first, 0 })
  vim.api.nvim_win_call(win, function()
    vim.cmd 'normal! zt'
  end)
end

---@param deck ShowMeDeck
---@param n integer
function M.open(deck, n)
  local view = assert(deck.views[n], 'show-me: no such view')
  vim.api.nvim_set_hl(0, 'ShowMeRange', { link = 'Visual', default = true })
  M.clear()
  reset_tab()
  local wins = layout.build(view.layout, #view.panes)
  for i, pane in ipairs(view.panes) do
    show_pane(wins[i], pane)
    vim.wo[wins[i]].winbar = winbar(deck, n, pane)
  end
  vim.api.nvim_set_current_win(wins[1])
  position = { deck = deck, view = n }
end

---Move `delta` views through the deck on screen. Only acts in the show-me tab.
---@param delta integer
function M.step(delta)
  if not position or vim.api.nvim_get_current_tabpage() ~= M.tab() then
    return
  end
  local n = position.view + delta
  if position.deck.views[n] then
    M.open(position.deck, n)
  end
end

--- Remove every show-me highlight.
function M.clear()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_clear_namespace(buf, M.NS, 0, -1)
    end
  end
end

function M.close()
  local tab = M.tab()
  if not tab then
    return
  end
  if #vim.api.nvim_list_tabpages() == 1 then
    vim.cmd 'tabnew'
  end
  vim.cmd('tabclose ' .. vim.api.nvim_tabpage_get_number(tab))
  M.on_tab_closed()
end

--- TabClosed handler: once the show-me tab is gone, however it was closed,
--- drop its highlights so they don't linger in the user's own windows.
function M.on_tab_closed()
  if not M.tab() then
    M.clear()
    position = nil
  end
end

return M
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `./test/run.sh show_me_render`
Expected: all `ok`.

- [ ] **Step 5: Commit**

```bash
git add lua/custom/show_me/render.lua test/spec/show_me_render_spec.lua
git commit -m "feat(show-me): render views in a dedicated tab"
```

---

### Task 5: Module entry point, RPC, and keymaps

This task has no spec of its own. `rpc`, `open` and `status` are exercised end to end through the real CLI and a child Neovim in Task 6, which is the only place they're reachable with an isolated state directory. This task's check is that the config still loads cleanly.

**Files:**
- Create: `lua/custom/show_me/init.lua`
- Modify: `init.lua`, after `require('custom.linear').setup()` (~line 197) and in the which-key group list (~line 408)

**Interfaces:**
- Consumes: `socket.listen`, `socket.hash` (Task 1); `deck.store`, `deck.view`, `deck.is_rejection` (Task 3); `render.open`, `render.on_tab_closed` (Task 4)
- Produces:
  - `show_me.setup()`
  - `show_me.rpc(args: string[]) -> string`. `args[1]` is the subcommand. The protocol for each command:
    - `deck <title>` replies `ok:deck <id>`
    - `view <id> <title-or-empty> <layout> <pane>...` replies `ok:view <n>`
    - `done <id>` replies `ok:done <id>`
    - `status` replies `ok:<3 lines>`
    - Any failure replies `error:<reason>`
  - `show_me.current() -> ShowMeDeck|nil`
  - `show_me.open(n: integer)`
  - `show_me.pick()`
  - `show_me.status() -> string`

- [ ] **Step 1: Implement `lua/custom/show_me/init.lua`**

```lua
--- show-me: lets terminal agents illustrate explanations in this Neovim.
---
--- An agent runs the `show-me` CLI (skills/show-me-nvim), which reaches this
--- instance over a socket derived from its startup cwd (`socket.lua`) and calls
--- `rpc()`. Agents build a *deck* of numbered *views* per explanation; a deck
--- becomes current when the agent marks it done, and the user opens its views
--- at their own pace with `<leader>v1`–`9`. Nothing here ever moves focus.

local decks = require 'custom.show_me.deck'
local render = require 'custom.show_me.render'
local socket = require 'custom.show_me.socket'

local M = {}

---@class ShowMeState
---@field scope string|nil Startup cwd this instance serves
---@field address string|nil Socket address, when listening
---@field store ShowMeStore|nil
---@field current ShowMeDeck|nil Deck the view keys act on

---@type ShowMeState
local state = {}

---@return ShowMeStore
function M.store()
  if not state.store then
    state.scope = state.scope or vim.fn.getcwd()
    state.store = decks.store(vim.fs.joinpath(vim.fn.stdpath 'state', 'show-me', socket.hash(state.scope)))
  end
  return state.store
end

---@param d ShowMeDeck
local function announce(d)
  local count = #d.views
  vim.schedule(function()
    vim.notify(('show-me: %s · %d view%s · <leader>v1'):format(d.title, count, count == 1 and '' or 's'), vim.log.levels.INFO)
  end)
end

---@type table<string, fun(args: string[]): string>
local COMMANDS = {
  deck = function(args)
    return ('deck %d'):format(M.store():create(args[1]).id)
  end,
  view = function(args)
    local id, title, layout_name = args[1], args[2], args[3]
    local view = decks.view(layout_name, vim.list_slice(args, 4), title ~= '' and title or nil)
    return ('view %d'):format(M.store():add_view(id, view))
  end,
  done = function(args)
    state.current = M.store():finish(args[1])
    announce(state.current)
    return ('done %d'):format(state.current.id)
  end,
  status = function()
    return M.status()
  end,
}

---Entry point for the `show-me` CLI. Never raises: the CLI reads `ok:<payload>`
---or `error:<reason>` and maps them to exit codes.
---@param args string[] Subcommand followed by its arguments
---@return string
function M.rpc(args)
  local command = COMMANDS[args[1] or '']
  if not command then
    return ('error:unknown command %q'):format(tostring(args[1]))
  end
  local ok, result = pcall(command, vim.list_slice(args, 2))
  if ok then
    return 'ok:' .. result
  elseif decks.is_rejection(result) then
    return 'error:' .. tostring(result)
  end
  return 'error:internal error: ' .. tostring(result)
end

---@return ShowMeDeck|nil
function M.current()
  state.current = state.current or M.store():latest_done()
  return state.current
end

---@return string
function M.status()
  local d = M.current()
  return table.concat({
    'scope: ' .. (state.scope or vim.fn.getcwd()),
    'socket: ' .. (state.address or 'not listening'),
    'current: ' .. (d and ('deck %d "%s" (%d views)'):format(d.id, d.title, #d.views) or 'none'),
  }, '\n')
end

---Open view `n` of the current deck.
---@param n integer
function M.open(n)
  local d = M.current()
  if not d then
    vim.notify('show-me: no deck yet; ask an agent to show you something', vim.log.levels.WARN)
  elseif not d.views[n] then
    vim.notify(('show-me: "%s" has %d view%s'):format(d.title, #d.views, #d.views == 1 and '' or 's'), vim.log.levels.WARN)
  else
    render.open(d, n)
  end
end

---Pick a recent deck; it becomes current and opens at view 1.
function M.pick()
  local items = vim.tbl_map(function(d)
    local lines = {}
    for i, v in ipairs(d.views) do
      lines[#lines + 1] = ('%d. %s  [%s]'):format(i, v.title or '', v.layout)
      for _, p in ipairs(v.panes) do
        lines[#lines + 1] = '     ' .. vim.fn.fnamemodify(p.path, ':~:.') .. (p.first and (':%d-%d'):format(p.first, p.last) or '')
      end
    end
    return { text = d.title, deck = d, preview = { text = table.concat(lines, '\n') } }
  end, M.store():list_done())

  if #items == 0 then
    vim.notify('show-me: no decks yet', vim.log.levels.WARN)
    return
  end

  Snacks.picker {
    title = 'Show-me decks',
    items = items,
    preview = 'preview',
    format = function(item)
      return {
        { ('%3d  '):format(item.deck.id), 'SnacksPickerComment' },
        { item.deck.title, 'SnacksPickerLabel' },
        { ('  %d views'):format(#item.deck.views), 'SnacksPickerComment' },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        state.current = item.deck
        render.open(item.deck, 1)
      end
    end,
  }
end

function M.setup()
  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
      state.scope = vim.fn.getcwd()
      local address, reason = socket.listen(state.scope)
      state.address = address
      if not address then
        vim.notify('show-me: agents cannot reach this Neovim; ' .. reason, vim.log.levels.INFO)
      end
    end,
  })
  vim.api.nvim_create_autocmd('TabClosed', { callback = render.on_tab_closed })
  vim.api.nvim_create_user_command('ShowMe', function(o)
    local n = tonumber(o.args)
    if o.args == '' then
      M.pick()
    elseif n then
      M.open(n)
    else
      vim.notify('show-me: usage :ShowMe [view number]', vim.log.levels.WARN)
    end
  end, { nargs = '?', desc = 'Open show-me view N of the current deck, or pick a deck' })
end

return M
```

- [ ] **Step 2: Wire it into `init.lua`**

Insert this after `require('custom.linear').setup()` (around line 197), before the Linear keymap block:

```lua
-- show-me: terminal agents (Claude Code, Codex, Cursor) show code here through
-- the `show-me` CLI in skills/show-me-nvim. setup() claims the socket they find
-- this instance by; views only ever open when asked for, with the keys below.
require('custom.show_me').setup()

-- stylua: ignore start
for n = 1, 9 do
  vim.keymap.set('n', '<leader>v' .. n, function() require('custom.show_me').open(n) end, { desc = ('Show-me: [v]iew %d'):format(n) })
end
vim.keymap.set('n', ']v', function() require('custom.show_me.render').step(1) end, { desc = 'Show-me: next view' })
vim.keymap.set('n', '[v', function() require('custom.show_me.render').step(-1) end, { desc = 'Show-me: previous view' })
vim.keymap.set('n', '<leader>vd', function() require('custom.show_me').pick() end, { desc = 'Show-me: pick a [d]eck' })
vim.keymap.set('n', '<leader>vq', function() require('custom.show_me.render').close() end, { desc = 'Show-me: [q]uit the view tab' })
-- stylua: ignore end
```

Then add this to the which-key group list, after `{ '<leader>l', group = '[L]inear' },`:

```lua
        { '<leader>v', group = '[V]iew (show-me)' },
```

- [ ] **Step 3: Verify the config loads and the module wires up**

Run:
```bash
nvim --headless -c 'lua print(vim.fn.exists(":ShowMe"), vim.fn.maparg("<leader>v1", "n") ~= "")' -c 'qa' 2>&1
./test/run.sh
```
Expected: the first command prints `2 true` with no errors. Every spec passes, including the existing ones.

- [ ] **Step 4: Commit**

```bash
git add lua/custom/show_me/init.lua init.lua
git commit -m "feat(show-me): wire RPC entry point, :ShowMe and <leader>v keys"
```

---

### Task 6: The `show-me` CLI and the end-to-end spec

**Files:**
- Create: `skills/show-me-nvim/scripts/show-me` (mode 755)
- Test: `test/spec/show_me_cli_spec.lua`

**Interfaces:**
- Consumes: `show_me.rpc` protocol (Task 5); `socket.path`, `socket.hash` (Task 1)
- Produces: the CLI surface below, which `SKILL.md` (Task 7) documents:
  - `show-me deck <title...>` prints `deck <id>`
  - `show-me view <id> <layout> <pane>... [--title T]` prints `view <n>`
  - `show-me done <id>` prints `done <id>`
  - `show-me status`
  - `show-me socket` prints the candidate socket paths, nearest first, without any RPC

- [ ] **Step 1: Write the failing test**

`test/spec/show_me_cli_spec.lua`:

```lua
local T = require 'test.helpers'
local socket = require 'custom.show_me.socket'

-- End to end: the real CLI against a child Neovim running this config. The
-- child gets its own XDG_STATE_HOME so decks never land in the user's state,
-- and is SIGKILLed at the end so no exit hooks (auto-session) run.

local CLI = vim.fn.fnamemodify('skills/show-me-nvim/scripts/show-me', ':p')
local root = vim.fn.tempname()
local scope = root .. '/scope'
local deeper = scope .. '/sub/deeper'
vim.fn.mkdir(deeper, 'p')
local file = deeper .. "/it's 100%.py"
vim.fn.writefile(vim.tbl_map(tostring, vim.fn.range(1, 30)), file)

---@return vim.SystemCompleted
local function run(...)
  return vim.system({ CLI, ... }, { cwd = deeper, text = true }):wait()
end

---@param r vim.SystemCompleted
---@param code integer
---@param needle string
---@param label string
local function expect(r, code, needle, label)
  T.eq(r.code, code, label .. ': exit ' .. code)
  local out = code == 0 and r.stdout or r.stderr
  T.ok(out:find(needle, 1, true), ('%s: output has %q (got %q)'):format(label, needle, out))
end

-- Pure derivation, no Neovim needed: nearest candidate first, ancestors after.
local candidates = vim.split(vim.trim(run('socket').stdout), '\n')
T.eq(candidates[1], socket.path(deeper), 'CLI and Lua derive the same socket path')
T.ok(vim.tbl_contains(candidates, socket.path(scope)), 'CLI walks up to ancestor scopes')

expect(run 'status', 3, socket.path(scope), 'no Neovim yet')
expect(run 'view', 2, 'usage', 'missing arguments')

local child = vim.system({ 'nvim', '--headless' }, { cwd = scope, env = { XDG_STATE_HOME = root .. '/state' } })
local up = vim.wait(20000, function()
  return vim.uv.fs_stat(socket.path(scope)) ~= nil
end, 100)
T.ok(up, 'child Neovim claimed its scope socket')

---Evaluate Lua in the child and return its stdout.
---@param lua string
---@return vim.SystemCompleted
local function remote(lua)
  return vim.system({ 'nvim', '--server', socket.path(scope), '--remote-expr', ('luaeval("%s")'):format(lua) }, { text = true }):wait()
end

T.eq(remote("require('custom.show_me').open(1) or 'quiet'").stdout, 'quiet', 'opening with no deck notifies instead of raising')

expect(run('deck', 'How', 'it works'), 0, 'deck 1', 'deck')
expect(run('view', '1', 'cols2', "it's 100%.py:2-4", "../deeper/it's 100%.py:10", '--title', "it's 100%"), 0, 'view 1', 'view')
expect(run('view', '1', 'cols2', "it's 100%.py"), 1, 'cols2 takes 2 panes, got 1', 'pane count')
expect(run('view', '1', 'grid', 'a', 'b'), 1, 'unknown layout', 'layout')
expect(run('view', '1', 'single', 'missing.py'), 1, 'no readable file', 'missing file')
expect(run('view', '1', 'single', "it's 100%.py:25-40"), 1, 'past the end', 'range past EOF')
expect(run('view', '1', 'single', 'nodir/x.py'), 1, 'no such directory', 'missing directory')
expect(run('done', '1'), 0, 'done 1', 'done')
expect(run('view', '1', 'single', "it's 100%.py"), 1, 'already done', 'closed deck')
expect(run 'status', 0, 'deck 1 "How it works"', 'status')

-- What the child persisted: absolute physical paths, quoting intact.
local saved = vim.json.decode(table.concat(vim.fn.readfile(('%s/state/nvim/show-me/%s/1.json'):format(root, socket.hash(scope))), '\n'))
local real = vim.uv.fs_realpath(file)
T.eq(saved.views[1].title, "it's 100%", 'title survived shell and Vimscript quoting')
T.eq(saved.views[1].panes[1].path, real, 'relative pane stored as absolute physical path')
T.eq(saved.views[1].panes[2].path, real, '../ pane resolved to the same file')
T.eq(saved.views[1].panes[2].first, 10, 'N pane highlights line N')

T.eq(remote("(function() require('custom.show_me').open(1) return #vim.api.nvim_tabpage_list_wins(0) end)()").stdout, '2', 'user opens view 1 in the child')

-- SHOW_ME_SOCKET bypasses resolution entirely.
local direct = vim.system({ CLI, 'status' }, { cwd = '/', text = true, env = { SHOW_ME_SOCKET = socket.path(scope) } }):wait()
T.eq(direct.code, 0, 'SHOW_ME_SOCKET reaches the child from anywhere')
local bogus = vim.system({ CLI, 'status' }, { cwd = '/', text = true, env = { SHOW_ME_SOCKET = root .. '/nope.sock' } }):wait()
T.eq(bogus.code, 3, 'dead SHOW_ME_SOCKET: exit 3')

child:kill(9)
T.done()
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `./test/run.sh show_me_cli`
Expected: FAIL, because the CLI doesn't exist yet (`ENOENT` from `vim.system`).

- [ ] **Step 3: Implement the CLI**

`skills/show-me-nvim/scripts/show-me`:

```bash
#!/usr/bin/env bash
# show-me: illustrate an explanation in the user's Neovim. See ../SKILL.md.
#
# Finds the Neovim serving this directory (or an ancestor) through a socket
# named by a hash of that directory, and calls require('custom.show_me').rpc.
# Keep the socket derivation in step with lua/custom/show_me/socket.lua.
#
# Portable to macOS bash 3.2 and BSD userland: no realpath, readlink -f, sed -i,
# associative arrays or ${x,,}.

set -uo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  show-me deck <title>
  show-me view <deck-id> <layout> <file[:N[-M]]>... [--title <text>]
  show-me done <deck-id>
  show-me status
  show-me socket
layouts: single (1 pane), cols2 (2), cols3 (3), main-stack (3-4)
EOF
  exit 2
}

die() {
  printf 'show-me: %s\n' "$1" >&2
  exit "${2:-1}"
}

physical() { (cd "$1" 2>/dev/null && pwd -P); }

sha16() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-16
  else
    printf '%s' "$1" | shasum -a 256 | cut -c1-16
  fi
}

socket_dir() { printf '/tmp/show-me-%s' "$(id -u)"; }

# Where the upward search starts: the main checkout when inside a git repo, so
# linked worktrees resolve to it; otherwise the current directory.
start_dir() {
  local common
  if common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    physical "$common/.."
  else
    physical .
  fi
}

# Candidate socket paths, nearest scope first.
candidates() {
  local dir sockets
  dir=$(start_dir) || dir=$(physical .)
  sockets=$(socket_dir)
  while :; do
    printf '%s/%s.sock\n' "$sockets" "$(sha16 "$dir")"
    [ "$dir" = / ] && break
    dir=$(dirname "$dir")
  done
}

alive() { nvim --server "$1" --remote-expr 1 >/dev/null 2>&1; }

resolve_socket() {
  if [ -n "${SHOW_ME_SOCKET:-}" ]; then
    alive "$SHOW_ME_SOCKET" || die "no Neovim answering at SHOW_ME_SOCKET=$SHOW_ME_SOCKET" 3
    printf '%s' "$SHOW_ME_SOCKET"
    return 0
  fi
  local dir sock tried=""
  dir=$(socket_dir)
  if [ -d "$dir" ] && [ ! -O "$dir" ]; then
    die "$dir is owned by another user; refusing to use it" 3
  fi
  while IFS= read -r sock; do
    if [ -S "$sock" ] && alive "$sock"; then
      printf '%s' "$sock"
      return 0
    fi
    tried="$tried
  $sock"
  done < <(candidates)
  die "no Neovim is serving this directory or any parent; tried:$tried" 3
}

# path[:range] -> /physical/dir/file[:range]
absolute() {
  local spec=$1 path range="" dir
  if [[ $spec =~ ^(.+):([0-9-]+)$ ]]; then
    path=${BASH_REMATCH[1]}
    range=":${BASH_REMATCH[2]}"
  else
    path=$spec
  fi
  dir=$(physical "$(dirname "$path")") || die "no such directory for $path" 1
  printf '%s/%s%s' "${dir%/}" "$(basename "$path")" "$range"
}

# Arguments as a Vimscript list of single-quoted strings.
vim_list() {
  local out="" arg q="'" nl='
'
  for arg in "$@"; do
    arg=${arg//$nl/ }
    arg=${arg//$q/$q$q}
    out="$out${out:+,}'$arg'"
  done
  printf '[%s]' "$out"
}

rpc() {
  local sock out
  sock=$(resolve_socket) || exit $?
  out=$(nvim --server "$sock" --remote-expr "luaeval(\"require('custom.show_me').rpc(_A)\", $(vim_list "$@"))" 2>&1) ||
    die "Neovim at $sock could not run show-me (is this config loaded?): $out" 3
  case $out in
    ok:*) printf '%s\n' "${out#ok:}" ;;
    error:*) die "${out#error:}" 1 ;;
    *) die "unexpected reply from Neovim: $out" 1 ;;
  esac
}

cmd=${1:-}
[ $# -gt 0 ] && shift

case $cmd in
  deck)
    [ $# -ge 1 ] || usage
    rpc deck "$*"
    ;;
  view)
    [ $# -ge 3 ] || usage
    id=$1 layout=$2
    shift 2
    title=""
    panes=()
    while [ $# -gt 0 ]; do
      case $1 in
        --title)
          [ $# -ge 2 ] || usage
          title=$2
          shift 2
          ;;
        *)
          pane=$(absolute "$1") || exit $?
          panes+=("$pane")
          shift
          ;;
      esac
    done
    [ ${#panes[@]} -ge 1 ] || usage
    rpc view "$id" "$title" "$layout" "${panes[@]}"
    ;;
  done)
    [ $# -eq 1 ] || usage
    rpc done "$1"
    ;;
  status) rpc status ;;
  socket) candidates ;;
  *) usage ;;
esac
```

Then: `chmod +x skills/show-me-nvim/scripts/show-me`

- [ ] **Step 4: Run the tests and confirm they pass, under the system bash too**

Run:
```bash
./test/run.sh show_me_cli
/bin/bash -n skills/show-me-nvim/scripts/show-me && /bin/bash --version | head -1
./test/run.sh
```
Expected: `show_me_cli` reports all `ok`. `bash -n` is silent, and on macOS it reports `3.2.57`. The full suite passes.

If `env = { XDG_STATE_HOME = ... }` in `vim.system` *replaces* the environment rather than merging with it, and the child can't find `nvim` or `HOME`, add `clear_env = false`. That's the documented default, so this is only a fallback.

- [ ] **Step 5: Commit**

```bash
git add skills/show-me-nvim/scripts/show-me test/spec/show_me_cli_spec.lua
git commit -m "feat(show-me): add the show-me CLI and end-to-end spec"
```

---

### Task 7: The agent skill and installer

**Files:**
- Create: `skills/show-me-nvim/SKILL.md`
- Create: `skills/show-me-nvim/install.sh` (mode 755)

**Interfaces:**
- Consumes: the CLI surface from Task 6, verbatim

- [ ] **Step 1: Write `SKILL.md`**

````markdown
---
name: show-me-nvim
description: Show code in the user's Neovim while explaining it. Use when answering questions about a codebase where the explanation spans more than one location (call chains, data flow, before/after, two branches), or when the user asks to be shown, pointed at, or walked through code. Builds a deck of numbered multi-pane views the user opens at their own pace.
---

# show-me-nvim

The user reads your explanation in the terminal and has Neovim open in another
window. With `show-me` you prepare **views** in Neovim (files side by side,
scrolled to and highlighting the lines you mean) and refer to them in your
answer. Nothing pops up: the user gets a notification and opens each view
with `<leader>v1`…`<leader>v9` as they read.

Run `show-me` from the repository you are discussing. If it is not on `PATH`,
use `scripts/show-me` in this skill's directory.

## When to use it

- The explanation touches **two or more locations**: a caller and its callee, a
  pipeline, a type and where it's built, the same function on two branches.
- The user says "show me", "point me to", "walk me through", "where is".

Skip it for a single short snippet you can quote inline, or when no repository
is involved.

## Workflow

1. `show-me deck "<what this explanation is about>"`: prints `deck <id>`.
2. One `show-me view <id> <layout> <pane>... --title "<short caption>"` per
   illustration. Each call prints `view <n>`, and those numbers are what you cite.
3. `show-me done <id>`. The user is notified only now, so send it after the
   last view and before you write your answer.
4. In your answer, cite views by number and pane position: *"the token is
   minted in `mint()` (**view 1**, top-right pane)…"* Start the answer with
   one line telling the user that views are ready (for example
   "Views 1–3 are ready in Neovim: `<leader>v1`").

## Panes

`path`, `path:N` (highlight line N), or `path:N-M`. Paths are relative to your
working directory or absolute. A path into another worktree (`../repo-feature/src/x.py`)
works, which is how you compare branches.

Keep ranges to **about 60 lines or fewer** so they fit in a pane. Highlight
the lines that matter, not the whole file.

## Layouts

Only these four exist:

| Layout | Panes | Use for |
|---|---|---|
| `single` | 1 | one focal piece of code |
| `cols2` | 2 | compare/contrast; caller and callee; before and after |
| `cols3` | 3 | a three-stage pipeline, read left to right |
| `main-stack` | 3-4 | one primary file (left, wide) plus 2-3 helpers stacked on the right |

Pane 1 is always left (and top-left in `main-stack`); the rest follow in
reading order. Prefer **one idea per view** and more views over packed panes.
A deck holds at most 9 views.

## Example

```sh
show-me deck "How a login request is authenticated"            # deck 4
show-me view 4 main-stack src/auth.py:40-88 src/token.py:10-30 src/db.py:5-19 --title "Login path"
show-me view 4 cols2 ../app-feature/src/auth.py:40-90 src/auth.py:40-88 --title "Feature branch vs main"
show-me done 4
```

## Errors

| Exit | Meaning | What to do |
|---|---|---|
| 1 | Request rejected; stderr says why (bad layout, pane count, missing file, range past end of file) | Fix that view and resend it. Earlier views in the deck are kept |
| 2 | Usage error | Check the argument order above |
| 3 | No Neovim reachable | If you are sandboxed, ask the user to approve running `show-me` outside the sandbox. Otherwise tell the user that their Neovim isn't serving this directory, and continue the explanation without views |

Never send `done` twice, and never rebuild a deck to "refresh" it. If you need
different views, start a new deck.
````

- [ ] **Step 2: Write `install.sh`**

```bash
#!/usr/bin/env bash
# Link the show-me-nvim skill into each agent's skills directory, and the CLI
# onto PATH. Safe to re-run; works with BSD (macOS) and GNU ln.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

for dir in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.cursor/skills"; do
  mkdir -p "$dir"
  ln -sfn "$here" "$dir/show-me-nvim"
  echo "linked $dir/show-me-nvim"
done

mkdir -p "$HOME/.local/bin"
ln -sf "$here/scripts/show-me" "$HOME/.local/bin/show-me"
echo "linked ~/.local/bin/show-me (ensure ~/.local/bin is on PATH)"
```

Then: `chmod +x skills/show-me-nvim/install.sh`

- [ ] **Step 3: Verify**

Run: `/bin/bash -n skills/show-me-nvim/install.sh && head -4 skills/show-me-nvim/SKILL.md`
Expected: no syntax errors, and the frontmatter shows `name: show-me-nvim`.

Don't run `install.sh` yourself. It writes into the user's home directory, so the user runs it (see Task 8's docs).

- [ ] **Step 4: Commit**

```bash
git add skills/show-me-nvim/SKILL.md skills/show-me-nvim/install.sh
git commit -m "feat(show-me): add the show-me-nvim agent skill and installer"
```

---

### Task 8: Cross-platform CI and documentation

**Files:**
- Create: `.github/workflows/specs.yml`
- Modify: `README.md` (new section after the work-context section; find the last `## ` heading in the custom-workflow part of the file), `CHEATSHEET.md` (keymap table)

- [ ] **Step 1: Write the workflow**

`.github/workflows/specs.yml`:

```yaml
# Run the show-me specs on both platforms this config is used on. The specs
# load the real config, so it is linked into ~/.config/nvim and plugins are
# restored from lazy-lock.json first.
name: Specs
on:
  pull_request:
  push:
    branches: [master]

jobs:
  specs:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: stable
      - name: Link config
        run: mkdir -p ~/.config && ln -s "$GITHUB_WORKSPACE" ~/.config/nvim
      - name: Restore plugins
        run: nvim --headless "+Lazy! restore" +qa
      - name: Run show-me specs
        run: ./test/run.sh show_me
```

- [ ] **Step 2: Validate the workflow locally where possible**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/specs.yml'))" && echo valid`
Expected: `valid`. The real check is the first CI run after pushing. Note in the PR description that this workflow is new and unproven.

- [ ] **Step 3: README section**

Add a `## show-me: agents point at code` section that covers:

```markdown
## show-me: agents point at code

Terminal agents (Claude Code, Codex, Cursor) can show code in this Neovim while
they explain it. An agent builds a *deck* of numbered views (one of four
layouts: `single`, `cols2`, `cols3`, `main-stack`, each pane a file with a
highlighted range) and you open them as you read. Nothing ever pops up
uninvited; you get a notification.

**Install the skill** (once per machine; links into `~/.claude/skills`,
`~/.codex/skills`, `~/.cursor/skills`, and `~/.local/bin/show-me`):

    ./skills/show-me-nvim/install.sh

**How agents find this Neovim:** on startup it listens on
`/tmp/show-me-<uid>/<hash of cwd>.sock`. The CLI walks up from the agent's main
checkout (worktrees map to their main checkout) and uses the first socket that
answers, so an agent anywhere under `~/repos` reaches a Neovim started in
`~/repos`. `show-me status` shows what it found. `SHOW_ME_SOCKET` overrides it.

| Keys | Action |
|---|---|
| `<leader>v1`…`<leader>v9` | Open view N of the current deck |
| `]v` / `[v` | Next / previous view (in the show-me tab) |
| `<leader>vd` | Pick a recent deck |
| `<leader>vq` | Close the show-me tab |

**Sandboxed agents.** `show-me` connects to a unix socket, which agent sandboxes
may block. Allow it explicitly:

- Claude Code: add `"Bash(show-me:*)"` to `permissions.allow`. If sandboxing is
  on, also list it in `sandbox.excludedCommands`.
- Codex: approve `show-me` when prompted, or run with a sandbox mode that allows
  local sockets.
- Cursor: add `show-me` to the terminal command allowlist.
```

- [ ] **Step 4: CHEATSHEET rows**

Add the same four keymap rows to `CHEATSHEET.md`, in the table or section that lists `<leader>l` keys, under a `show-me` heading that matches that file's existing format. Read the file first and copy its structure.

- [ ] **Step 5: Final full verification**

Run: `./test/run.sh && nvim --headless -c 'qa' 2>&1 | head -5`
Expected: `all specs passed`, and Neovim starts headless with no errors.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/specs.yml README.md CHEATSHEET.md
git commit -m "docs(show-me): document the skill and add a macOS/Ubuntu spec matrix"
```

---

## After all tasks

- The user runs `./skills/show-me-nvim/install.sh` on both machines.
- Manual smoke test, in a real session: start `nvim` in `~/repos`. Ask Claude
  Code in a separate Ghostty window, from `~/repos/kickstart.nvim`, to "show me
  how show-me resolves sockets". Expect a notification, then `<leader>v1` opens
  the views.
