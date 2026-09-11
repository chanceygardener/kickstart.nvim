--- Linear issues, via `schpet/linear-cli`.
---
--- Deliberately a thin client over the CLI rather than a Lua API client: the same
--- binary backs the terminal and the coding agents, so there is one auth, one
--- command vocabulary, and no second integration to debug.
---
--- Two CLI behaviors this leans on, both verified against v2.6.0:
---   * `linear issue view` emits raw markdown when stdout is not a TTY — no ANSI,
---     no pager — so the issue buffer needs no formatter of its own.
---   * `linear issue query --json` returns nodes without a description, so the
---     search preview has to fetch per-selection rather than up front.

local M = {}

--- Shown once per session rather than on every keypress.
local warned_missing = false

--- Whether the CLI is usable, complaining at most once if not.
---@return boolean
function M.available()
  if vim.fn.executable 'linear' == 1 then
    return true
  end

  if not warned_missing then
    warned_missing = true
    vim.notify('linear: CLI not found — install with `brew install schpet/tap/linear`', vim.log.levels.ERROR)
  end
  return false
end

--- Turn a non-zero CLI exit into one useful line.
---
--- Distinguishes an auth problem from an ordinary miss, because "no such issue"
--- and "you are not logged in" want completely different responses from the user.
---@param result vim.SystemCompleted
---@return string
local function error_message(result)
  local err = vim.trim((result.stderr or '') .. ' ' .. (result.stdout or ''))

  if err:lower():match 'auth' or err:lower():match 'unauthor' or err:lower():match 'api key' then
    return 'not authenticated — run `linear auth login`'
  end
  if err == '' then
    return ('command failed (exit %d)'):format(result.code)
  end

  return err:gsub('%s+', ' ')
end

--- Open a scratch buffer holding an issue's markdown.
---
--- Named `linear://ENG-123` so viewing the same issue twice reuses the buffer
--- instead of stacking duplicates.
---@param id string
---@param markdown string
---@param opts? { split?: boolean }
local function open_buffer(id, markdown, opts)
  opts = opts or {}
  local name = 'linear://' .. id

  local buf
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match(vim.pesc(name) .. '$') then
      buf = b
      break
    end
  end

  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(markdown, '\n', { plain = true }))

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false

  if opts.split then
    vim.cmd 'vsplit'
  end
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo[0].wrap = true
  vim.wo[0].linebreak = true

  vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf, desc = 'Close issue' })
end

--- True when the current tab is a review surface, so an issue should open beside
--- the diff rather than replacing it.
---@return boolean
local function in_review_tab()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype or ''
    if ft:match '^Diffview' or ft:match '^octo' then
      return true
    end
  end
  return false
end

--- Fetch an issue's markdown and display it.
---@param id string
---@param opts? { split?: boolean }
function M.view(id, opts)
  if not M.available() then
    return
  end

  id = id:upper()

  vim.system({ 'linear', 'issue', 'view', id }, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      vim.notify(('linear: %s (%s)'):format(error_message(result), id), vim.log.levels.ERROR)
      return
    end

    local markdown = vim.trim(result.stdout or '')
    if markdown == '' then
      vim.notify('linear: no content returned for ' .. id, vim.log.levels.WARN)
      return
    end

    open_buffer(id, markdown, opts)
  end))
end

--- Prompt for an identifier, then view it.
---@param id? string
function M.prompt_view(id)
  if id and id ~= '' then
    return M.view(id)
  end

  vim.ui.input({ prompt = 'Linear issue (e.g. ENG-1934): ' }, function(input)
    if input and vim.trim(input) ~= '' then
      M.view(vim.trim(input))
    end
  end)
end

--- View the ticket for the current branch's PR.
---
--- Opens beside the diff when a review is on screen, which is the case this is
--- most useful in: reading requirements against the change that implements them.
function M.current()
  if not M.available() then
    return
  end

  local ctx = require('custom.work').get()
  if not ctx then
    vim.notify('linear: no current story — pick one with <leader>lw, or look one up with <leader>lv', vim.log.levels.WARN)
    return
  end

  M.view(ctx.issue, { split = in_review_tab() })
end

--- Open the current issue in the browser.
function M.open_in_browser()
  if not M.available() then
    return
  end

  local ctx = require('custom.work').get()
  if not (ctx and ctx.issue) then
    vim.notify('linear: no current issue to open', vim.log.levels.WARN)
    return
  end

  vim.system { 'linear', 'issue', 'view', ctx.issue, '-w' }
end

--- One search result, flattened out of the CLI's node shape.
---@param node table
---@return table
local function to_item(node)
  local state = node.state and node.state.name or ''
  local team = node.team and node.team.key or ''

  return {
    identifier = node.identifier,
    title = node.title or '',
    url = node.url,
    state = state,
    team = team,
    text = table.concat({ node.identifier or '', node.title or '', state, team }, ' '),
  }
end

--- Search Linear and open the results in a picker.
---
--- Defaults to every team. A repo is often worked by more than one Linear team but
--- `linear.toml` names only one, so scoping to it would silently omit other teams'
--- issues — and since this exists mainly to catch duplicates before filing, a
--- false negative is the expensive failure. `opts.this_team` narrows on demand.
---@param query? string
---@param opts? { this_team?: boolean }
function M.search(query, opts)
  opts = opts or {}

  if not M.available() then
    return
  end

  if not query or vim.trim(query) == '' then
    vim.ui.input({ prompt = 'Search Linear: ' }, function(input)
      if input and vim.trim(input) ~= '' then
        M.search(vim.trim(input), opts)
      end
    end)
    return
  end

  local cmd = { 'linear', 'issue', 'query', '--search', query, '--json' }
  if not opts.this_team then
    table.insert(cmd, '--all-teams')
  end

  vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      vim.notify('linear: ' .. error_message(result), vim.log.levels.ERROR)
      return
    end

    local ok, decoded = pcall(vim.json.decode, result.stdout or '')
    if not ok or type(decoded) ~= 'table' or type(decoded.nodes) ~= 'table' then
      vim.notify('linear: could not parse search results', vim.log.levels.ERROR)
      return
    end

    if #decoded.nodes == 0 then
      vim.notify(('linear: no issues matching %q'):format(query), vim.log.levels.INFO)
      return
    end

    local items = vim.tbl_map(to_item, decoded.nodes)

    Snacks.picker {
      title = ('Linear: %s%s'):format(query, opts.this_team and ' (this team)' or ''),
      items = items,
      format = function(item)
        return {
          { ('%-10s'):format(item.identifier), 'SnacksPickerLabel' },
          { ' ' .. item.title, 'SnacksPickerFile' },
          { item.state ~= '' and ('  (%s)'):format(item.state) or '', 'SnacksPickerComment' },
        }
      end,
      -- Search results carry no description, so the full issue is fetched only for
      -- whatever is highlighted. `preview.cmd` streams it in asynchronously and
      -- disables the PTY when `ft` is set, which keeps the markdown ANSI-free.
      preview = function(ctx)
        return Snacks.picker.preview.cmd({ 'linear', 'issue', 'view', ctx.item.identifier }, ctx, { ft = 'markdown' })
      end,
      confirm = function(picker, item)
        picker:close()
        if item then
          M.view(item.identifier)
        end
      end,
      actions = {
        copy_id = function(picker, item)
          if item then
            vim.fn.setreg('+', item.identifier)
            vim.notify('linear: copied ' .. item.identifier, vim.log.levels.INFO)
          end
          picker:close()
        end,
        open_browser = function(picker, item)
          if item and item.url then
            vim.ui.open(item.url)
          end
          picker:close()
        end,
      },
      win = {
        input = {
          keys = {
            ['<c-y>'] = { 'copy_id', mode = { 'n', 'i' } },
            ['<c-o>'] = { 'open_browser', mode = { 'n', 'i' } },
          },
        },
      },
    }
  end))
end

--- Register the user commands.
function M.setup()
  vim.api.nvim_create_user_command('LinearView', function(cmd)
    M.prompt_view(cmd.args)
  end, { nargs = '?', desc = 'View a Linear issue' })

  vim.api.nvim_create_user_command('LinearSearch', function(cmd)
    M.search(cmd.args)
  end, { nargs = '?', desc = 'Search Linear issues (all teams)' })

  vim.api.nvim_create_user_command('LinearCurrent', function()
    M.current()
  end, { desc = "View this branch's Linear issue" })
end

return M
