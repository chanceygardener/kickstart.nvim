-- snacks.nvim — a collection of small QoL modules
-- https://github.com/folke/snacks.nvim
--
-- This config is deliberately additive: the modules that would compete with
-- plugins already in this config (picker/telescope, explorer/neo-tree,
-- terminal/claude-code.nvim) are left disabled. See the `enabled = false`
-- block below for the reasoning on each.

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
    -- auto-detects an installed picker, which resolves to telescope here.
    dashboard = {
      enabled = true,
      preset = {
        -- The upstream default includes a "Restore Session" entry, which
        -- requires a session manager this config doesn't have. Omitted.
        keys = {
          { icon = ' ', key = 'f', desc = 'Find File', action = ":lua Snacks.dashboard.pick('files')" },
          { icon = ' ', key = 'n', desc = 'New File', action = ':ene | startinsert' },
          { icon = ' ', key = 'g', desc = 'Find Text', action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = ' ', key = 'r', desc = 'Recent Files', action = ":lua Snacks.dashboard.pick('oldfiles')" },
          { icon = ' ', key = 'c', desc = 'Config', action = ":lua Snacks.dashboard.pick('files', { cwd = vim.fn.stdpath('config') })" },
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

    -- Replaces `vim.ui.input` only. telescope-ui-select keeps `vim.ui.select`.
    input = { enabled = true },

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
    picker = { enabled = false }, -- telescope.nvim owns picking
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
  end,
}
