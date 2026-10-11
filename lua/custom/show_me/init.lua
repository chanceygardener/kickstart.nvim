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
