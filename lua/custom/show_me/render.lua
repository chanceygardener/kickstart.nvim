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
