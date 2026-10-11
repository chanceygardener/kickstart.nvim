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
