-- csvview.nvim — aligns delimited files into readable columns
-- https://github.com/hat0uma/csvview.nvim

return {
  'hat0uma/csvview.nvim',

  -- Loaded either by the commands below (for delimited files that aren't
  -- detected as csv/tsv — logs, pipe-separated exports) or by the `require`
  -- in the FileType autocmd in `init`, which lazy.nvim resolves on demand.
  cmd = { 'CsvViewEnable', 'CsvViewDisable', 'CsvViewToggle', 'CsvViewInfo' },

  ---@module "csvview"
  ---@type CsvView.Options
  opts = {
    parser = {
      -- Treat these as comment lines rather than data rows.
      comments = { '#', '//' },
    },
    view = {
      -- Draw a vertical rule between columns instead of highlighting the raw
      -- delimiter, so the buffer reads as a table.
      display_mode = 'border',
    },
    -- Buffer-local while a CSV view is active, so these do not shadow the
    -- global <Tab>/<Enter> bindings anywhere else.
    keymaps = {
      textobject_field_inner = { 'if', mode = { 'o', 'x' } },
      textobject_field_outer = { 'af', mode = { 'o', 'x' } },
      jump_next_field_end = { '<Tab>', mode = { 'n', 'v' } },
      jump_prev_field_end = { '<S-Tab>', mode = { 'n', 'v' } },
      jump_next_row = { '<Enter>', mode = { 'n', 'v' } },
      jump_prev_row = { '<S-Enter>', mode = { 'n', 'v' } },
    },
  },

  keys = {
    { '<leader>tv', '<cmd>CsvViewToggle<cr>', desc = '[T]oggle CSV [v]iew' },
  },

  init = function()
    -- Auto-enable on csv/tsv. This lives in `init` (which runs at startup)
    -- rather than in `config`: the plugin is lazy-loaded, so an autocmd
    -- registered after loading would miss the very FileType event that
    -- triggered the load. The `require` here is what pulls the plugin in.
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'csv', 'tsv' },
      group = vim.api.nvim_create_augroup('csvview-auto-enable', { clear = true }),
      callback = function(ev)
        require('csvview').enable(ev.buf)
      end,
    })
  end,
}
