local T = require 'test.helpers'
local socket = require 'custom.show_me.socket'

-- The show-me tab must never be written into an auto-session session: `t:show_me`
-- is not saved, so a restored copy would be an orphan tab that the next
-- `<leader>v1` duplicates. `nvim -l` doesn't load plugins, so this drives a
-- child Neovim with the full config, in a throwaway cwd whose session is deleted
-- afterwards. SIGKILLed at the end so its own exit hooks never save anything.

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
vim.fn.writefile({ 'one', 'two' }, dir .. '/a.lua')

local child = vim.system({ 'nvim', '--headless' }, { cwd = dir, env = { XDG_STATE_HOME = dir .. '/state' } })
local up = vim.wait(20000, function()
  return vim.uv.fs_stat(socket.path(dir)) ~= nil
end, 100)
T.ok(up, 'child Neovim is up')

---Evaluate Lua in the child and return its trimmed stdout.
---@param lua string
---@return string
local function remote(lua)
  local r = vim.system({ 'nvim', '--server', socket.path(dir), '--remote-expr', ('luaeval("%s")'):format(lua) }, { text = true }):wait()
  return vim.trim(r.stdout .. r.stderr)
end

local TAB_STATE = "require('custom.show_me.render').tab() and 'open' or 'closed'"

T.eq(
  remote(
    "(function() require('custom.show_me.render').open({ id = 1, title = 'S', created_at = 0, done = true, views = { { layout = 'single', panes = { { path = vim.fn.getcwd() .. '/a.lua' } } } } }, 1) return "
      .. TAB_STATE
      .. ' end)()'
  ),
  'open',
  'show-me tab is open before saving'
)
T.eq(remote("(function() vim.cmd('AutoSession save') return " .. TAB_STATE .. ' end)()'), 'closed', 'saving a session closes the show-me tab first')

remote "(function() vim.cmd('AutoSession delete') return 'ok' end)()"
child:kill(9)
T.done()
