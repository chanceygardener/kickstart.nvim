-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  {
    'madmaxieee/unclash.nvim',
    lazy = false,
    opts = {
      action_buttons = { enabled = true },
      annotations = { enabled = true },
    },
    keys = {
      { ']x', function() require('unclash').next_conflict() end, desc = 'Next merge conflict' },
      { '[x', function() require('unclash').prev_conflict() end, desc = 'Previous merge conflict' },
      { '<leader>gco', function() require('unclash').accept_current() end, desc = 'Accept current (ours)' },
      { '<leader>gci', function() require('unclash').accept_incoming() end, desc = 'Accept incoming (theirs)' },
      { '<leader>gcb', function() require('unclash').accept_both() end, desc = 'Accept both' },
      { '<leader>gcm', function() require('unclash').open_merge_editor() end, desc = 'Open merge editor' },
    },
  },
  {
    'greggh/claude-code.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    config = function()
      require('claude-code').setup()
    end,
  },
  {
    'MagicDuck/grug-far.nvim',
    dependencies = {
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    opts = {},
    cmd = { 'GrugFar', 'GrugFarWithin' },
    keys = {
      {
        '<leader>sR',
        function()
          require('grug-far').open()
        end,
        mode = 'n',
        desc = '[S]earch [R]eplace (grug-far)',
      },
      {
        '<leader>sR',
        function()
          require('grug-far').with_visual_selection()
        end,
        mode = 'x',
        desc = '[S]earch [R]eplace (grug-far, selection)',
      },
      {
        '<leader>sv',
        function()
          require('grug-far').open { visualSelectionUsage = 'operate-within-range' }
        end,
        mode = 'x',
        desc = '[S]earch replace in [V]isual range',
      },
    },
  },
  {
    'klepp0/nvim-baml-syntax',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    ft = 'baml',
    config = function()
      require('baml_syntax').setup()
    end,
  },
}
