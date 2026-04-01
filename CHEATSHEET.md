# Neovim Kickstart Cheatsheet

## File Tree (Neo-tree)

| Keybinding | Action |
|------------|--------|
| `\` | Toggle file tree (open/close) |
| `\` (in tree) | Close file tree |

## Basic Movement (Normal Mode)

| Keybinding | Action |
|------------|--------|
| `h` | Move left |
| `j` | Move down |
| `k` | Move up |
| `l` | Move right |
| `w` | Jump to start of next word |
| `b` | Jump to start of previous word |
| `0` | Jump to start of line |
| `$` | Jump to end of line |
| `gg` | Jump to start of file |
| `G` | Jump to end of file |

## Selecting/Highlighting Text (Visual Mode)

| Keybinding | Action |
|------------|--------|
| `v` | Enter visual mode (character-wise) |
| `V` | Enter visual mode (line-wise) |
| `Ctrl+v` | Enter visual block mode (column selection) |
| `o` (in visual mode) | Move to other end of selection |
| `aw` (in visual mode) | Select a word |
| `ap` (in visual mode) | Select a paragraph |
| `a)` or `a(` | Select around parentheses |
| `a]` or `a[` | Select around brackets |
| `a}` or `a{` | Select around braces |
| `a"` or `a'` | Select around quotes |

## Deleting/Cutting

| Keybinding | Action |
|------------|--------|
| `dd` | Delete (cut) current line |
| `d` + motion | Delete with motion (e.g., `dw` = delete word) |
| `D` | Delete from cursor to end of line |
| `x` | Delete character under cursor |
| `X` | Delete character before cursor |
| Visual + `d` | Delete selected text |

## Copying (Yanking)

| Keybinding | Action |
|------------|--------|
| `yy` | Yank (copy) current line |
| `y` + motion | Yank with motion (e.g., `yw` = yank word) |
| `Y` | Yank to end of line |
| Visual + `y` | Yank selected text |

## Pasting

| Keybinding | Action |
|------------|--------|
| `p` | Paste after cursor/line |
| `P` | Paste before cursor/line |

## Undo/Redo

| Keybinding | Action |
|------------|--------|
| `u` | Undo |
| `Ctrl+z` | Undo (GUI-style) |
| `Ctrl+r` | Redo |
| `Ctrl+Shift+z` | Redo (GUI-style) |

## Split Windows

### Creating Splits

| Keybinding | Action |
|------------|--------|
| `:split` or `:sp` | Horizontal split |
| `:vsplit` or `:vsp` | Vertical split |
| `Ctrl+w s` | Horizontal split |
| `Ctrl+w v` | Vertical split |

### Navigating Between Splits

| Keybinding | Action |
|------------|--------|
| `Ctrl+h` | Move to left window |
| `Ctrl+j` | Move to lower window |
| `Ctrl+k` | Move to upper window |
| `Ctrl+l` | Move to right window |

### Managing Splits

| Keybinding | Action |
|------------|--------|
| `Ctrl+w q` | Close current window |
| `Ctrl+w o` | Close all windows except current |
| `Ctrl+w =` | Make all windows equal size |
| `Ctrl+w _` | Maximize window height |
| `Ctrl+w |` | Maximize window width |

## Modes

| Keybinding | Action |
|------------|--------|
| `i` | Enter insert mode (before cursor) |
| `a` | Enter insert mode (after cursor) |
| `I` | Enter insert mode (start of line) |
| `A` | Enter insert mode (end of line) |
| `o` | Open new line below and enter insert mode |
| `O` | Open new line above and enter insert mode |
| `Esc` | Return to normal mode |

## Search and Replace

| Keybinding | Action |
|------------|--------|
| `/` | Search forward |
| `?` | Search backward |
| `n` | Next search result |
| `N` | Previous search result |
| `Esc` | Clear search highlights |
| `:%s/old/new/g` | Replace all occurrences in file |
| `:%s/old/new/gc` | Replace all with confirmation |

## Find and Replace (grug-far.nvim)

[grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim): project-wide (and multi-file) find/replace using **ripgrep** (`rg`), with a dedicated buffer for editing the search, replacement, paths, and flags. See `:h grug-far` for full options.

### Opening grug-far (global keymaps)

Leader is `Space`. These load the plugin when used.

| Keybinding | Mode | Action |
|------------|------|--------|
| `Space s R` | Normal | Open grug-far for find/replace |
| `Space s R` | Visual | Open grug-far with the selected text as the search string |
| `Space s v` | Visual | Find/replace **only within** the current visual selection (line/character range) |

### Commands

| Command | Action |
|---------|--------|
| `:GrugFar` | Open a new grug-far buffer (supports modifiers like `:botright GrugFar`; in visual mode, pre-fills search from the selection) |
| `:GrugFarWithin` | Like `:GrugFar`, but limit search/replace to the visual selection range |

### Inside the grug-far buffer

Buffer-local maps use **`<localleader>`**, which is also `Space` in this config (same as the main leader). Defaults include:

| Keybinding | Action (typical default) |
|------------|--------------------------|
| `Space r` | Run **Replace** (apply replacement) |
| `Space c` | **Close** the grug-far buffer (confirms if a job is running) |
| `Enter` | **Goto** file/location for the result under the cursor (normal mode) |

The buffer shows inline help for actions and inputs. Use `:h grug-far` for engines (`rg` vs ast-grep), sync, history, quickfix, and more.

### Requirements and health

- Needs **ripgrep** (`rg`) on your `PATH` (already expected by kickstart).
- If something fails, run `:checkhealth grug-far`.

## File Operations

| Keybinding | Action |
|------------|--------|
| `:w` | Save file |
| `:q` | Quit |
| `:wq` | Save and quit |
| `:q!` | Quit without saving |
| `Space sf` | Search files |
| `Space sg` | Search by grep |
| `Space Space` | Find existing buffers |

## LSP (Code Intelligence)

| Keybinding | Action |
|------------|--------|
| `gd` | Go to definition |
| `gr` | Go to references |
| `gI` | Go to implementation |
| `Space rn` | Rename symbol |
| `Space ca` | Code action |
| `Space f` | Format buffer |

## Merge Conflicts (unclash.nvim)

| Keybinding | Action |
|------------|--------|
| `]x` | Jump to next merge conflict |
| `[x` | Jump to previous merge conflict |
| `Space gco` | Accept current (ours) |
| `Space gci` | Accept incoming (theirs) |
| `Space gcb` | Accept both |
| `Space gcm` | Open 3-way merge editor |

## Claude Code (claude-code.nvim)

| Keybinding | Action |
|------------|--------|
| `Ctrl+,` | Toggle Claude Code window (normal/terminal) |
| `Space ac` | Toggle Claude Code window (alt) |
| `Ctrl+h/j/k/l` | Navigate between windows (in terminal) |
| `Ctrl+f` | Page down in Claude terminal |
| `Ctrl+b` | Page up in Claude terminal |
| `:ClaudeCode` | Toggle Claude Code terminal |
| `:ClaudeCodeContinue` | Resume most recent conversation |
| `:ClaudeCodeResume` | Show conversation picker |

## Quick Tips

- The leader key is `Space`
- Clipboard is synced with OS (copy/paste works with system clipboard)
- Type `:Tutor` for an interactive Neovim tutorial
- Type `Space sh` to search help documentation
- Type `:checkhealth` to diagnose issues
