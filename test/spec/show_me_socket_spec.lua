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
vim.fn.mkdir(socket.dir(), 'p', tonumber('700', 8))
vim.fn.writefile({}, socket.path(stale_scope))
local addr, reason = socket.listen(stale_scope)
T.eq(addr, socket.path(stale_scope), 'stale socket file replaced by a live server')
T.nil_(reason, 'no reason when listening')
T.eq(vim.uv.fs_stat(socket.dir()).mode % 512, tonumber('700', 8), 'socket dir is private')
if addr then
  vim.fn.serverstop(addr)
end

-- A live socket owned by another Neovim is left alone.
local live_scope = tmp .. '/live'
vim.fn.mkdir(live_scope, 'p')
local other = vim.system { 'nvim', '--headless', '--clean', '--listen', socket.path(live_scope) }
vim.wait(5000, function()
  return vim.uv.fs_stat(socket.path(live_scope)) ~= nil
end, 50)
addr, reason = socket.listen(live_scope)
T.nil_(addr, 'does not steal a live socket')
T.ok(reason and reason:find('another Neovim', 1, true), 'explains why it did not listen')
other:kill(9)

T.done()
