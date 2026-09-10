-- octo.nvim — GitHub PR review without the browser
-- https://github.com/pwntester/octo.nvim
--
-- Diffview answers "what changed"; Octo answers "what did we decide about it".
-- Inline comments, threads, suggestions and review submission all live on GitHub,
-- which makes the review itself the handoff protocol to an agent: leave comments
-- here, then tell the agent to pull and address unresolved threads.
--
-- Works through the authenticated `gh` CLI. Note that Projects v2 features need a
-- scope this setup doesn't grant by default — `gh auth refresh -s read:project`
-- if you ever want them.

return {
  'pwntester/octo.nvim',

  cmd = 'Octo',

  dependencies = {
    'nvim-lua/plenary.nvim',
    'folke/snacks.nvim',
    { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
  },

  ---@module "octo"
  opts = {
    -- telescope is not installed — snacks.picker owns every picker in this config.
    picker = 'snacks',

    -- Put the local checkout on the right-hand side of a review so LSP, edits and
    -- formatting work on real files instead of blobs fetched from the API.
    use_local_fs = true,

    reviews = {
      auto_show_threads = true,
      focus = 'right',
      show_virtual_text = true,
    },

    file_panel = {
      size = 14,
      icons = true,
    },

    -- Matches the diffview keymaps deliberately: `]f` file, `]t` thread. These are
    -- also the review keys that matter most, and mapping them to bracket motions
    -- keeps them clear of the `<localleader>` overlap described below.
    mappings = {
      review_diff = {
        select_next_entry = { lhs = ']f', desc = 'Next changed file' },
        select_prev_entry = { lhs = '[f', desc = 'Previous changed file' },
        next_thread = { lhs = ']t', desc = 'Next review thread' },
        prev_thread = { lhs = '[t', desc = 'Previous review thread' },
      },
    },
  },

  keys = {
    { '<leader>do', '<cmd>Octo review start<cr>', desc = '[D]iff: [o]pen GitHub review' },
    { '<leader>dp', '<cmd>Octo pr list<cr>', desc = '[D]iff: GitHub [p]R list' },
    { '<leader>dS', '<cmd>Octo review submit<cr>', desc = '[D]iff: [S]ubmit GitHub review' },
  },
}
