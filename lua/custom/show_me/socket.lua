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
