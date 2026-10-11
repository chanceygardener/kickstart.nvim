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
