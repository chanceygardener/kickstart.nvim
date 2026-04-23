return {
  {
    'gelguy/wilder.nvim',
    event = 'CmdlineEnter',
    dependencies = {
      'romgrk/fzy-lua-native',
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      local wilder = require 'wilder'

      wilder.setup {
        modes = { ':', '/', '?' },
        use_python_remote_plugin = 0,
      }

      wilder.set_option('pipeline', {
        wilder.branch(
          wilder.cmdline_pipeline {
            fuzzy = 1,
            fuzzy_filter = wilder.lua_fzy_filter(),
          },
          wilder.vim_search_pipeline()
        ),
      })

      wilder.set_option('renderer', wilder.renderer_mux {
        [':'] = wilder.popupmenu_renderer(
          wilder.popupmenu_border_theme {
            highlighter = wilder.lua_fzy_highlighter(),
            left = { ' ', wilder.popupmenu_devicons() },
            right = { ' ', wilder.popupmenu_scrollbar() },
            border = 'rounded',
          }
        ),
        ['/'] = wilder.wildmenu_renderer {
          highlighter = wilder.lua_fzy_highlighter(),
        },
        ['?'] = wilder.wildmenu_renderer {
          highlighter = wilder.lua_fzy_highlighter(),
        },
      })
    end,
  },
}
