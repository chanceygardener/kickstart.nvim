-- auto-session — saves and restores the session (buffers, layout, cwd) per directory
-- https://github.com/rmagatti/auto-session
--
-- Requires `vim.o.sessionoptions` to include `localoptions`; that is set in
-- init.lua next to the other options rather than here, so all option tweaking
-- stays in one place.

return {
  'rmagatti/auto-session',
  -- Must not be lazy: the restore has to happen during startup, before the
  -- dashboard decides whether to draw itself.
  lazy = false,

  ---@module "auto-session"
  ---@type AutoSession.Config
  opts = {
    -- Directories where a session would be noise rather than useful.
    suppressed_dirs = { '~/', '~/Downloads', '~/Desktop', '/tmp', '/' },

    -- Without this, quitting straight from the start screen saves a session
    -- containing only the dashboard, which then restores as an empty screen
    -- on every subsequent visit to that directory.
    bypass_save_filetypes = { 'snacks_dashboard' },

    -- A restored Neo-tree sidebar comes back as a broken, empty window, so
    -- close it before writing the session. It reopens with `\` as usual.
    -- 'checkhealth' is the upstream default, kept here since this replaces it.
    close_filetypes_on_save = { 'checkhealth', 'neo-tree' },

    -- auto-session ships backends for telescope/fzf-lua/snacks and picks
    -- whichever is present; here that resolves to snacks.picker. Drives
    -- `:AutoSession search` and `<leader>pf`.
    session_lens = {
      load_on_setup = true,
    },
  },

  keys = {
    { '<leader>ps', '<cmd>AutoSession save<cr>', desc = '[P]roject session [s]ave' },
    { '<leader>pr', '<cmd>AutoSession restore<cr>', desc = '[P]roject session [r]estore' },
    { '<leader>pd', '<cmd>AutoSession delete<cr>', desc = '[P]roject session [d]elete' },
    { '<leader>pf', '<cmd>AutoSession search<cr>', desc = '[P]roject session [f]ind' },
    { '<leader>pt', '<cmd>AutoSession toggle<cr>', desc = '[P]roject session auto-save [t]oggle' },
  },
}
