local T = require 'test.helpers'
local render = require 'custom.show_me.render'

local function numbered(n)
  return vim.tbl_map(tostring, vim.fn.range(1, n))
end

local a = vim.fn.tempname() .. '.lua'
local b = vim.fn.tempname() .. '.lua'
vim.fn.writefile(numbered(100), a)
vim.fn.writefile(numbered(10), b) -- the deck below claims lines 15-40: the file "shrank"

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
T.eq(vim.api.nvim_win_get_cursor(wins[1])[1], 10, 'range past EOF clamps to the last line')
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
