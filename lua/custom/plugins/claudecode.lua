-- claudecode.nvim — Claude Code as an IDE integration, not just a terminal
-- https://github.com/coder/claudecode.nvim
--
-- Replaces greggh/claude-code.nvim, which only embedded a terminal. This one runs
-- a WebSocket server speaking Claude Code's actual IDE protocol — the same one the
-- VS Code extension uses — so the agent can read the current file, selection,
-- cursor position and diagnostics, and can drive Neovim to open the files it finds.
-- That two-way link is the whole reason for the swap: an agent that can navigate
-- you to the code it's talking about is worth more than a chat pane in a split.
--
-- Terminal comes from snacks.nvim, which is already loaded at startup.
-- Note: the plugin describes itself as beta.

return {
  'coder/claudecode.nvim',

  dependencies = { 'folke/snacks.nvim' },

  cmd = {
    'ClaudeCode',
    'ClaudeCodeFocus',
    'ClaudeCodeSelectModel',
    'ClaudeCodeAdd',
    'ClaudeCodeSend',
    'ClaudeCodeTreeAdd',
    'ClaudeCodeStatus',
    'ClaudeCodeStart',
    'ClaudeCodeStop',
    'ClaudeCodeOpen',
    'ClaudeCodeClose',
    'ClaudeCodeDiffAccept',
    'ClaudeCodeDiffDeny',
    'ClaudeCodeCloseAllDiffs',
  },

  ---@module "claudecode"
  opts = {
    terminal = { provider = 'snacks' },
  },

  keys = {
    -- `<C-,>` is carried over from the previous integration — the muscle memory is
    -- worth more than matching the plugin's documented default.
    { '<C-,>', '<cmd>ClaudeCode<cr>', mode = { 'n', 't' }, desc = 'Toggle Claude Code' },

    { '<leader>ac', '<cmd>ClaudeCode<cr>', desc = '[A]I: toggle [c]laude' },
    { '<leader>af', '<cmd>ClaudeCodeFocus<cr>', desc = '[A]I: [f]ocus Claude' },
    { '<leader>ar', '<cmd>ClaudeCode --resume<cr>', desc = '[A]I: [r]esume session' },
    { '<leader>aC', '<cmd>ClaudeCode --continue<cr>', desc = '[A]I: [C]ontinue last session' },
    { '<leader>am', '<cmd>ClaudeCodeSelectModel<cr>', desc = '[A]I: select [m]odel' },
    { '<leader>ab', '<cmd>ClaudeCodeAdd %<cr>', desc = '[A]I: add current [b]uffer' },
    { '<leader>as', '<cmd>ClaudeCodeSend<cr>', mode = 'v', desc = '[A]I: [s]end selection' },
    {
      '<leader>as',
      '<cmd>ClaudeCodeTreeAdd<cr>',
      desc = '[A]I: add file from tree',
      ft = { 'neo-tree', 'snacks_picker_list' },
    },
    { '<leader>aa', '<cmd>ClaudeCodeDiffAccept<cr>', desc = '[A]I: [a]ccept diff' },
    { '<leader>ad', '<cmd>ClaudeCodeDiffDeny<cr>', desc = '[A]I: [d]eny diff' },
  },
}
