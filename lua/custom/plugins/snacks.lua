-- snacks.nvim — a collection of small QoL modules
-- https://github.com/folke/snacks.nvim
--
-- Modules that would compete with a plugin already configured here are left
-- disabled; see the `enabled = false` block below for the reasoning on each.
--
-- `picker` is the exception: it replaced telescope.nvim outright, because
-- telescope 0.1.x drives its preview highlighting through nvim-treesitter v1's
-- Lua API and throws on every preview against the v2 (`main`) branch this
-- config tracks. The `<leader>s*` keymaps kept their original kickstart keys.

return {
  'folke/snacks.nvim',
  -- Both are required by snacks: several modules (bigfile, quickfile,
  -- statuscolumn) must be in place before the first buffer is rendered.
  priority = 1000,
  lazy = false,

  ---@type snacks.Config
  opts = {
    -- Disable treesitter/LSP/etc. on very large files so they stay openable.
    bigfile = { enabled = true },
    -- Render the file before plugins load, so startup feels instant.
    quickfile = { enabled = true },

    -- Start screen. `preset.pick` is intentionally left unset: snacks
    -- auto-detects a picker, which now resolves to snacks' own.
    dashboard = {
      enabled = true,
      preset = {
        keys = {
          { icon = ' ', key = 'f', desc = 'Find File', action = ":lua Snacks.dashboard.pick('files')" },
          { icon = ' ', key = 'n', desc = 'New File', action = ':ene | startinsert' },
          { icon = ' ', key = 'g', desc = 'Find Text', action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = ' ', key = 'r', desc = 'Recent Files', action = ":lua Snacks.dashboard.pick('oldfiles')" },
          { icon = ' ', key = 'c', desc = 'Config', action = ":lua Snacks.dashboard.pick('files', { cwd = vim.fn.stdpath('config') })" },
          -- The action is hardcoded rather than using `section = 'session'`:
          -- that helper picks the first session manager it recognises, and its
          -- list has mini.nvim ahead of auto-session. mini.nvim is installed
          -- here (for ai/surround/comment/statusline) but mini.sessions is
          -- never set up, so the generic section resolves to a call that errors.
          { icon = ' ', key = 's', desc = 'Restore Session', action = ':AutoSession restore' },
          { icon = '󰒲 ', key = 'L', desc = 'Lazy', action = ':Lazy', enabled = package.loaded.lazy ~= nil },
          { icon = ' ', key = 'q', desc = 'Quit', action = ':qa' },
        },
      },
    },

    -- Replaces `vim.notify`. fidget.nvim keeps handling LSP progress, which
    -- goes through a separate channel, so the two do not overlap.
    notifier = { enabled = true, timeout = 3000 },

    -- Fills the slot left by the commented-out `kickstart.plugins.indent_line`.
    indent = { enabled = true },
    scope = { enabled = true },

    -- Consolidated gutter. Renders gitsigns' signs alongside folds/marks.
    statuscolumn = { enabled = true },

    -- LSP reference highlighting, navigable with ]] and [[ (mapped below).
    words = { enabled = true },

    input = { enabled = true },

    -- Replaces telescope. `ui_select` routes `vim.ui.select` through the
    -- picker, taking over what telescope-ui-select used to do.
    picker = {
      enabled = true,
      ui_select = true,
    },

    -- Opt-in modules used by the keymaps below.
    lazygit = { enabled = true },
    git = { enabled = true },
    gitbrowse = { enabled = true },
    scratch = { enabled = true },
    zen = { enabled = true },
    bufdelete = { enabled = true },
    rename = { enabled = true },
    toggle = { enabled = true },

    -- Deliberately off — each would compete with a plugin already configured
    -- here, or was declined during setup.

    explorer = { enabled = false }, -- neo-tree owns the file tree
    terminal = { enabled = false }, -- claude-code.nvim owns terminals
    scroll = { enabled = false },
    image = { enabled = false },
    dim = { enabled = false },
    animate = { enabled = false },
  },

  -- These use `<cmd>` strings rather than Lua callbacks purely for legibility:
  -- stylua expands every inline `function() ... end` across five lines, which
  -- turns this table into ~120 lines of noise. Behaviour is identical, and
  -- `<cmd>` preserves the count for the ]]/[[ motions below.
  keys = {
    -- [S]earch — these replace the telescope keymaps that used to live in
    -- init.lua. The key scheme is deliberately unchanged from kickstart's.
    { '<leader>sh', '<cmd>lua Snacks.picker.help()<cr>', desc = '[S]earch [H]elp' },
    { '<leader>sk', '<cmd>lua Snacks.picker.keymaps()<cr>', desc = '[S]earch [K]eymaps' },
    { '<leader>sf', '<cmd>lua Snacks.picker.files()<cr>', desc = '[S]earch [F]iles' },
    { '<leader>ss', '<cmd>lua Snacks.picker.pickers()<cr>', desc = '[S]earch [S]elect picker' },
    { '<leader>sw', '<cmd>lua Snacks.picker.grep_word()<cr>', desc = '[S]earch current [W]ord', mode = { 'n', 'x' } },
    { '<leader>sg', '<cmd>lua Snacks.picker.grep()<cr>', desc = '[S]earch by [G]rep' },
    { '<leader>sd', '<cmd>lua Snacks.picker.diagnostics()<cr>', desc = '[S]earch [D]iagnostics' },
    { '<leader>sr', '<cmd>lua Snacks.picker.resume()<cr>', desc = '[S]earch [R]esume' },
    { '<leader>s.', '<cmd>lua Snacks.picker.recent()<cr>', desc = '[S]earch Recent Files ("." for repeat)' },
    { '<leader>s/', '<cmd>lua Snacks.picker.grep_buffers()<cr>', desc = '[S]earch [/] in Open Files' },
    { '<leader>sn', "<cmd>lua Snacks.picker.files({ cwd = vim.fn.stdpath('config') })<cr>", desc = '[S]earch [N]eovim files' },
    { '<leader><leader>', '<cmd>lua Snacks.picker.buffers()<cr>', desc = '[ ] Find existing buffers' },
    { '<leader>/', '<cmd>lua Snacks.picker.lines()<cr>', desc = '[/] Fuzzily search in current buffer' },

    -- [G]it
    { '<leader>gg', '<cmd>lua Snacks.lazygit()<cr>', desc = 'Lazy[g]it' },
    { '<leader>gl', '<cmd>lua Snacks.lazygit.log()<cr>', desc = 'Lazygit [l]og' },
    { '<leader>gf', '<cmd>lua Snacks.lazygit.log_file()<cr>', desc = 'Lazygit current [f]ile history' },
    { '<leader>gb', '<cmd>lua Snacks.git.blame_line()<cr>', desc = 'Git [b]lame line' },
    { '<leader>gB', '<cmd>lua Snacks.gitbrowse()<cr>', desc = 'Git [B]rowse in browser', mode = { 'n', 'x' } },

    -- [B]uffer
    { '<leader>bd', '<cmd>lua Snacks.bufdelete()<cr>', desc = '[B]uffer [d]elete' },
    { '<leader>bo', '<cmd>lua Snacks.bufdelete.other()<cr>', desc = '[B]uffer delete [o]thers' },

    -- [N]otifications
    { '<leader>nh', '<cmd>lua Snacks.notifier.show_history()<cr>', desc = '[N]otification [h]istory' },
    { '<leader>nd', '<cmd>lua Snacks.notifier.hide()<cr>', desc = '[N]otification [d]ismiss' },

    -- [T]oggle — non-toggle bindings only; the Snacks.toggle-backed ones are
    -- registered in `config` below.
    { '<leader>tZ', '<cmd>lua Snacks.zen.zoom()<cr>', desc = '[T]oggle [Z]oom' },

    -- [R]ename
    { '<leader>rf', '<cmd>lua Snacks.rename.rename_file()<cr>', desc = '[R]ename [f]ile' },

    -- Scratch buffers
    { '<leader>.', '<cmd>lua Snacks.scratch()<cr>', desc = 'Toggle scratch buffer' },
    { '<leader>S', '<cmd>lua Snacks.scratch.select()<cr>', desc = 'Select [S]cratch buffer' },

    -- LSP reference navigation
    { ']]', '<cmd>lua Snacks.words.jump(vim.v.count1)<cr>', desc = 'Next reference', mode = { 'n', 't' } },
    { '[[', '<cmd>lua Snacks.words.jump(-vim.v.count1)<cr>', desc = 'Prev reference', mode = { 'n', 't' } },
  },

  config = function(_, opts)
    require('snacks').setup(opts)

    -- Snacks.toggle bindings are registered here rather than on the usual
    -- `User VeryLazy` autocmd: this plugin is already `lazy = false`, so the
    -- extra event hop buys nothing, and VeryLazy never fires under
    -- `nvim --headless`, which makes these keymaps untestable.
    --
    -- These join the existing `<leader>t` [T]oggle group. `<leader>th`
    -- (inlay hints) and `<leader>tb`/`<leader>tD` (gitsigns — currently
    -- commented out, but kept reserved) are deliberately avoided.
    Snacks.toggle.zen():map '<leader>tz'
    Snacks.toggle.line_number():map '<leader>tL'
    Snacks.toggle.diagnostics():map '<leader>tg'
    Snacks.toggle.indent():map '<leader>ti'
    Snacks.toggle.option('wrap', { name = 'Wrap' }):map '<leader>tw'
    Snacks.toggle.option('spell', { name = 'Spelling' }):map '<leader>ts'
    Snacks.toggle.option('conceallevel', { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2 }):map '<leader>tc'

    -- Hand a half-typed `:e some/path` over to the picker, seeded with what
    -- you've typed so far. Neovim's own cmdline completion expands one path
    -- segment at a time, so `lua/sna` never resolves to
    -- `lua/custom/plugins/snacks.lua`; the picker's matcher does, because it
    -- matches as a subsequence over the whole relative path.
    --
    -- This shadows `cedit` (<C-f> opens the cmdline window by default). `q:`
    -- still opens that window from normal mode, which is the usual route.
    vim.keymap.set('c', '<C-f>', function()
      -- Only take over `:` cmdlines; `/` and `?` keep the default behaviour.
      if vim.fn.getcmdtype() ~= ':' then
        return '<C-f>'
      end

      -- Drop the command name, then take the last argument as the path
      -- fragment, so multi-argument commands (`:Neotree reveal x/y`) seed on
      -- `x/y` rather than the whole tail. The command itself is discarded, so
      -- `:vs foo` opens in the current window rather than a split — pick the
      -- file, then move it if needed.
      local args = vim.fn.getcmdline():match '^%s*%S+%s+(.*)$' or ''
      local pattern = args:match '(%S+)%s*$' or ''

      -- Deferred so the picker opens after the cmdline has been dismissed.
      vim.schedule(function()
        Snacks.picker.files { pattern = pattern }
      end)

      return '<C-c>'
    end, { expr = true, desc = 'Hand cmdline path to picker' })
  end,
}
