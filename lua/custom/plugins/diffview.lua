-- diffview.nvim — branch-sized change sets as a first-class view
-- https://github.com/dlyongemallo/diffview.nvim
--
-- This is the maintained fork. Upstream `sindrets/diffview.nvim` has had no commit
-- since June 2024 with 130+ open issues; the fork is several hundred commits ahead
-- and is what Neogit migrated to. Same module name and config surface.
--
-- The point of this plugin here is change-set topology: when an agent produces a
-- branch, the useful question is "what changed and what should I look at next",
-- not "where does this file live". Neo-tree keeps owning filesystem topology.
--
-- Every entry point routes through `custom.review` so the base branch is resolved
-- once and consistently — see that module for why `main` is never assumed.

return {
  'dlyongemallo/diffview.nvim',

  cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory', 'DiffviewFocusFiles', 'DiffviewToggleFiles', 'DiffviewRefresh' },

  ---@module "diffview"
  opts = function()
    local actions = require 'diffview.actions'

    return {
      -- Points the HEAD end of a triple-dot range at the real working-tree files
      -- rather than blobs read out of git, so LSP and edits work inside the diff.
      default_args = {
        DiffviewOpen = { '--imply-local' },
      },

      file_panel = {
        listing_style = 'tree',
        tree_options = {
          flatten_dirs = true,
          folder_statuses = 'only_folded',
        },
        win_config = {
          position = 'left',
          width = 40,
        },
      },

      keymaps = {
        -- Navigation is deliberately named after the object being traversed, and
        -- matches octo.nvim's review diff: `]f` file, `]c` change, `]t` thread.
        -- Which review surface you're on shouldn't change the vocabulary.
        view = {
          { 'n', ']f', actions.select_next_entry, { desc = 'Next changed file' } },
          { 'n', '[f', actions.select_prev_entry, { desc = 'Previous changed file' } },
          { 'n', 'gf', actions.goto_file_edit, { desc = 'Open the real working-tree file' } },
          { 'n', '<leader>df', actions.focus_files, { desc = '[D]iff: [f]ocus changed files' } },
          { 'n', '<leader>dt', actions.toggle_files, { desc = '[D]iff: [t]oggle changed files' } },
        },
        file_panel = {
          { 'n', ']f', actions.select_next_entry, { desc = 'Next changed file' } },
          { 'n', '[f', actions.select_prev_entry, { desc = 'Previous changed file' } },
          { 'n', 'gf', actions.goto_file_edit, { desc = 'Open the real working-tree file' } },
          { 'n', '<leader>dt', actions.toggle_files, { desc = '[D]iff: [t]oggle changed files' } },
        },
      },
    }
  end,

  -- `custom.review` is required inside each callback rather than at the top of the
  -- file so this spec stays cheap to evaluate during lazy.nvim's startup scan.
  keys = {
    { '<leader>dr', function() require('custom.review').open_diff() end, desc = '[D]iff: [r]eview PR against resolved base' },
    { '<leader>dR', function() require('custom.review').pick_base { then_open = true } end, desc = '[D]iff: pick base branch and [R]eview' },
    { '<leader>db', function() require('custom.review').pick_base() end, desc = '[D]iff: set review [b]ase' },
    { '<leader>dB', function() require('custom.review').clear_base() end, desc = '[D]iff: clear review [B]ase' },
    { '<leader>dP', function() require('custom.review').prompt_pathspec() end, desc = '[D]iff: review with [P]athspec filter' },
    { '<leader>dn', function() require('custom.review').git_status_tree() end, desc = '[D]iff: changed files in [n]eo-tree' },
    { '<leader>dd', '<cmd>DiffviewOpen<cr>', desc = '[D]iff: working tree vs in[d]ex' },
    { '<leader>dh', '<cmd>DiffviewFileHistory %<cr>', desc = '[D]iff: file [h]istory' },
    { '<leader>dH', '<cmd>DiffviewFileHistory<cr>', desc = '[D]iff: repo [H]istory' },
    { '<leader>dc', '<cmd>DiffviewClose<cr>', desc = '[D]iff: [c]lose' },
  },
}
