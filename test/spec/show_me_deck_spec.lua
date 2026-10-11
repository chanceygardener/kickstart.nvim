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
