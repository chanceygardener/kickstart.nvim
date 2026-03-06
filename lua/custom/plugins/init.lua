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
}
