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

## Surround (mini.surround)

Add, delete, and replace surrounding characters (brackets, quotes, tags, etc.) with operator-style motions.

### Adding surroundings

| Keybinding | Action |
|------------|--------|
| `sa` + motion + char | Add surrounding around motion (`saiw)` = surround inner word with parens) |
| Visual + `sa` + char | Add surrounding around selection |

### Deleting surroundings

| Keybinding | Action |
|------------|--------|
| `sd` + char | Delete surrounding (`sd'` = delete surrounding single quotes) |

### Replacing surroundings

| Keybinding | Action |
|------------|--------|
| `sr` + old + new | Replace surrounding (`sr)'` = replace `)` with `'`) |

### Finding / highlighting surroundings

| Keybinding | Action |
|------------|--------|
| `sf` + char | Find next surrounding (move cursor to it) |
| `sF` + char | Find previous surrounding |
| `sh` + char | Highlight surrounding (briefly flashes it) |

### Surrounding characters reference

| Character | Surrounding added |
|-----------|-------------------|
| `)` or `(` | `(…)` |
| `]` or `[` | `[…]` |
| `}` or `{` | `{…}` |
| `>` or `<` | `<…>` |
| `'` | `'…'` |
| `"` | `"…"` |
| `` ` `` | `` `…` `` |
| `t` | HTML/XML tag (`<div>…</div>`) |

### Examples

| Keybinding | Before → After |
|------------|----------------|
| `saiw)` | `hello` → `(hello)` (cursor on word) |
| `saiw"` | `hello` → `"hello"` |
| `sd'` | `'hello'` → `hello` |
| `sr)"` | `(hello)` → `"hello"` |
| `sat<div>` | `hello` → `<div>hello</div>` |

## Cmdline Completion (wilder.nvim)

[wilder.nvim](https://github.com/gelguy/wilder.nvim) provides fuzzy-matched, scrollable
suggestions while typing commands (`:`), forward search (`/`), and backward search (`?`).
Suggestions appear automatically — no trigger key needed.

### Navigation

| Keybinding | Action |
|------------|--------|
| `Tab` | Next suggestion |
| `S-Tab` (Shift+Tab) | Previous suggestion |
| `Esc` | Dismiss suggestions / cancel cmdline |

### Modes Enhanced

| Mode | Trigger | Renderer | Completions |
|------|---------|----------|-------------|
| Command | `:` | Popupmenu (bordered, with devicons) | Commands, paths, history — fuzzy matched |
| Search forward | `/` | Wildmenu (bottom bar) | Buffer text / history |
| Search backward | `?` | Wildmenu (bottom bar) | Buffer text / history |

### Tips

- Suggestions appear automatically as you type — no extra keystroke required.
- The popupmenu for `:` shows file-type icons (requires Nerd Font) and a scrollbar.
- Fuzzy matching works mid-string: typing `bw` will surface `bufwipe`, etc.
- wilder does not interfere with picker searches or `<leader>` keymaps.
- Run `:checkhealth wilder` to diagnose any issues.

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

## Fuzzy Finding (snacks.picker)

Replaced telescope.nvim. Keys are unchanged from the kickstart scheme.

| Keybinding | Action |
|------------|--------|
| `Space sf` | Search [F]iles |
| `Space sg` | Search by [G]rep (whole project) |
| `Space sw` | Search current [W]ord (also works on a visual selection) |
| `Space s/` | Search in open files only |
| `Space sh` | Search [H]elp |
| `Space sk` | Search [K]eymaps |
| `Space sd` | Search [D]iagnostics |
| `Space sn` | Search [N]eovim config files |
| `Space sr` | [R]esume the last picker |
| `Space s.` | Recent files |
| `Space ss` | [S]elect a picker (list of all pickers) |
| `Space Space` | Find existing buffers |
| `Space /` | Fuzzily search lines in the current buffer |

LSP navigation (`gd`, `gr`, `gI`, `Space D`, `Space ds`, `Space ws`) also runs
through the picker. `vim.ui.select` prompts use it too.

## Deep Path Completion (`:E`)

Neovim's built-in `:e` completion expands **one path segment at a time**, so
`lua/sna` never resolves to `lua/custom/plugins/snacks.lua`. Use **`:E`**
instead — same as `:edit`, but its `Tab` completion matches what you type as a
subsequence across every path under the cwd. Results appear in the usual
wilder popup; no picker window opens.

| You type | `Tab` resolves to |
|----------|-------------------|
| `:E lua/snacks` | `lua/custom/plugins/snacks.lua` |
| `:E cust/auto` | `lua/custom/plugins/auto-session.lua` |
| `:E kick/wild` | `lua/kickstart/plugins/wilder.lua` |

`:E` also accepts `!` (`:E! file`) and, with no argument, reloads the current
buffer — matching `:edit` in both cases.

Implemented in `lua/custom/fuzzy_edit.lua`.

### Notes

- Short fragments match loosely (`lua/sna` returns ~11 hits, best first); a few
  more characters narrow it.
- The file list is cached per directory for 5s and rebuilt on `:cd`, so
  completion stays responsive — a 8,500-file tree scans in ~35ms and matches
  in ~3ms.
- `.git`, `node_modules`, `.venv`, `__pycache__`, `target`, `dist`, `build`
  and similar are not scanned.
- To make plain `:e` use it, add `vim.cmd 'cnoreabbrev e E'`. Left off by
  default because it shadows `:e`'s other forms (`:e #`, `:e +42 file`,
  netrw URLs).

### Alternative: hand a half-typed path to the picker

While the `:` prompt is **still open** (before pressing Enter), `Ctrl+f` hands
what you've typed to the picker, seeded as a filter.

- Only in command-line mode. In normal mode `Ctrl+f` is still page-down.
- Takes the **last** argument, dropping the command, so `:vs foo` + `Ctrl+f`
  opens in the current window rather than a split.
- `/` and `?` searches keep `Ctrl+f`'s default behaviour.
- Shadows `cedit` (cmdline window); use `q:` from normal mode for that.

**Grep needs ripgrep.** `Space sg`, `Space sw` and `Space s/` return nothing
without it — install with `brew install ripgrep`. Adding `fd`
(`brew install fd`) also makes `Space sf` faster; without either, file search
falls back to `find`, which works but is slower.

## LSP (Code Intelligence)

| Keybinding | Action |
|------------|--------|
| `gd` | Go to definition |
| `gr` | Go to references |
| `gI` | Go to implementation |
| `Space rn` | Rename symbol |
| `Space ca` | Code action |
| `Space f` | Format buffer |

## Commenting (mini.comment)

| Keybinding | Mode | Action |
|------------|------|--------|
| `Ctrl+/` | Normal | Toggle comment on current line |
| `Ctrl+/` | Visual | Toggle comment on selected lines |
| `gcc` | Normal | Toggle comment on current line (vim motion) |
| `gc` + motion | Normal | Toggle comment over motion (`gcip` = comment paragraph) |

Toggle is bidirectional — comments if uncommented, uncomments if already commented. Comment syntax is detected automatically per filetype via treesitter.

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

## QoL Modules (snacks.nvim)

Configured additively in `lua/custom/plugins/snacks.lua` — the snacks picker
explorer is **disabled** so Neo-tree keeps owning the file tree. The picker
**replaced telescope.nvim**.

### Git

| Keybinding | Action |
|------------|--------|
| `Space gg` | Open lazygit (repo root) |
| `Space gl` | Lazygit log |
| `Space gf` | Lazygit history for the current file |
| `Space gb` | Git blame the current line |
| `Space gB` | Open file/selection on the git host in a browser (also visual) |

Requires `lazygit` on `PATH` (`brew install lazygit`).

### Buffers, scratch and notifications

| Keybinding | Action |
|------------|--------|
| `Space bd` | Delete current buffer, keeping the window layout intact |
| `Space bo` | Delete all *other* buffers |
| `Space .`  | Toggle a scratch buffer (per project + filetype, persisted) |
| `Space S`  | Pick from existing scratch buffers |
| `Space nh` | Show notification history |
| `Space nd` | Dismiss all visible notifications |
| `Space rf` | Rename the current file (updates LSP references) |

### Toggles

Join the existing `Space t` toggle group.

| Keybinding | Action |
|------------|--------|
| `Space tz` | Zen mode |
| `Space tZ` | Zoom (maximise current window) |
| `Space tL` | Line numbers |
| `Space tg` | Diagnostics |
| `Space ti` | Indent guides |
| `Space tw` | Line wrap |
| `Space ts` | Spell check |
| `Space tc` | Conceal level |

### Reference navigation

| Keybinding | Action |
|------------|--------|
| `]]` | Jump to next reference of the symbol under the cursor |
| `[[` | Jump to previous reference |

### Always-on behaviour (no keybinding)

- **Dashboard** — start screen when opening `nvim` with no file
- **Notifier** — replaces `vim.notify` popups (fidget still handles LSP progress)
- **Indent + scope** — indent guides with the current scope highlighted
- **Statuscolumn** — combined gutter for signs, git marks and folds
- **Bigfile** — disables treesitter/LSP on very large files so they stay openable
- **Quickfile** — renders the file before plugins finish loading
- **Input/Select** — popups for `vim.ui.input` and `vim.ui.select`

## Sessions (auto-session)

One session per project directory, holding your open buffers, window layout
and cwd. Running `nvim` with no arguments in a directory you've worked in
before restores it automatically; a directory with no session shows the
dashboard instead, where `s` restores on demand.

Sessions are stored in `~/.local/share/nvim/sessions/`.

| Keybinding / Command | Action |
|----------------------|--------|
| `Space ps` | Save the session for the current directory |
| `Space pr` | Restore the session for the current directory |
| `Space pd` | Delete the session for the current directory |
| `Space pf` | Find/search sessions (picker) |
| `Space pt` | Toggle auto-saving on/off for this session |
| `:AutoSession purgeOrphaned` | Remove sessions for deleted directories |

### Things worth knowing

- **No session is saved** in `~`, `~/Downloads`, `~/Desktop`, `/tmp` or `/`.
- **Opening a single file** (`nvim foo.txt`) disables auto-save for that run,
  so a quick edit can't overwrite the session for that directory.
- **Neo-tree is closed before saving.** A restored sidebar comes back broken,
  so reopen it with `\` after a restore.
- **Terminals are not restored** — `sessionoptions` deliberately omits
  `terminal` so Claude Code terminals don't come back dead.
- The dashboard is never saved as a session, so quitting from the start screen
  won't leave you with an empty session on the next visit.

## CSV / TSV Files (csvview.nvim)

`.csv` and `.tsv` files are aligned into columns automatically on open, using
`border` display mode — columns are separated by a vertical rule and the header
row sticks to the top while you scroll. Lines starting with `#` or `//` are
treated as comments rather than data.

| Keybinding / Command | Action |
|----------------------|--------|
| `Space tv`        | Toggle CSV view on/off |
| `:CsvViewEnable`  | Enable alignment for the current buffer |
| `:CsvViewDisable` | Disable alignment (back to raw text) |
| `:CsvViewToggle`  | Toggle alignment |
| `:CsvViewInfo`    | Show row/column statistics for the buffer |

### Inside an aligned CSV buffer

These are buffer-local — they only apply while CSV view is active, and do not
affect `Tab` or `Enter` anywhere else.

| Keybinding | Action |
|------------|--------|
| `Tab`       | Jump to end of next field |
| `Shift+Tab` | Jump to end of previous field |
| `Enter`     | Jump to next row (same column) |
| `Shift+Enter` | Jump to previous row (same column) |
| `if`        | Text object: inner field (e.g. `cif` to change a cell) |
| `af`        | Text object: outer field, including the delimiter |

For delimited files that aren't detected as csv/tsv — pipe- or
semicolon-separated exports, some log formats — open the file and run
`:CsvViewEnable`. The delimiter is guessed from `,`, tab, `;`, `|`, `:`
and space.

## LSP Coverage by Language

| Language / Format | Server | Notes |
|-------------------|--------|-------|
| Python | `pylsp` | black formatter, jedi fuzzy completion, isort |
| YAML | `yamlls` | schema validation: docker-compose, GitHub Actions, k8s |
| JSON / GeoJSON | `jsonls` | GeoJSON schema auto-validates `*.geojson` |
| TypeScript / JS | `ts_ls` | AWS CDK (TypeScript), general TS/JS |
| Bash / shell | `bashls` | shell scripts |
| SQL | — | no LSP; linting + formatting via sqlfluff, syntax via treesitter |
| Lua | `lua_ls` | Neovim config |
| Makefile | — | no LSP; linting via checkmake, syntax via treesitter |

All servers are installed automatically via Mason on first launch.

## Linting (nvim-lint)

Linters run automatically on `BufWritePost` and `InsertLeave`. Diagnostics appear inline alongside LSP diagnostics.

| Filetype | Linter | Install |
|----------|--------|---------|
| YAML | `yamllint` | Mason (auto) |
| Dockerfile | `hadolint` | Mason (auto) |
| SQL | `sqlfluff` | Mason (auto); set dialect in `.sqlfluff`: `[sqlfluff]\ndialect = postgres` |
| Makefile | `checkmake` | Mason (auto) |
| Markdown | `markdownlint` | Mason (auto) |

## Python (pylsp + conform.nvim)

pylsp is configured with jedi fuzzy completion and black as the LSP formatter. conform.nvim runs
`isort` then `black` on every save and via `<leader>f`.

**JSON** is formatted by `jq` (install separately: `brew install jq`). **YAML** formatting uses
the `yamlls` LSP fallback — no extra tool needed.

**Jinja2** (`.jinja2` / `.j2`): treesitter syntax highlighting only — no LSP. Files are detected
as `jinja` filetype automatically.

Run `:Mason` on first launch and wait for all tools to install before opening language files.

| Keybinding / Command | Action |
|----------------------|--------|
| `<leader>f`          | Format buffer: isort → black (conform.nvim) |
| `<leader>ca`         | Code action (pylsp) |
| `<leader>rn`         | Rename symbol |
| `gd`                 | Go to definition (jedi) |
| `gr`                 | Find references |
| `K`                  | Hover documentation |
| `:lsp info`          | Show active LSP clients (replaces removed `:LspInfo`) |
| `:lsp restart`       | Restart LSP server (replaces removed `:LspRestart`) |
| `:lsp log`           | Open LSP log (replaces removed `:LspLog`) |

## Quick Tips

- The leader key is `Space`
- Clipboard is synced with OS (copy/paste works with system clipboard)
- Type `:Tutor` for an interactive Neovim tutorial
- Type `Space sh` to search help documentation
- Type `:checkhealth` to diagnose issues
- Neovim 0.12 removed `:LspInfo` / `:LspRestart` / `:LspLog` — use `:lsp info` / `:lsp restart` / `:lsp log` instead
- Fuzzy finding is `snacks.picker`, not telescope. Telescope 0.1.x drives its
  preview highlighting through nvim-treesitter v1's Lua API, which v2 (`main`,
  used here) removed, so every preview threw an error.
- Install `ripgrep` for grep pickers to return results (`brew install ripgrep`).
