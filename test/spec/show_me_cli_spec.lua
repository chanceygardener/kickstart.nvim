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
