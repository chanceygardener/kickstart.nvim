# show-me-nvim — Design

**Date:** 2026-10-11
**Status:** approved in conversation, spec under review

## Problem

Coding agents (Claude Code, Codex, Cursor's CLI, and occasionally a custom agent) run
in a **separate terminal window** next to Neovim. When asked about a codebase, they can
only quote code in chat. Embedded agent plugins (claudecode.nvim and friends) can open
one file at a time but have not been mature enough to rely on, and agents outside
Neovim cannot reach them at all.

We want any terminal agent to be able to **illustrate an explanation in the user's
Neovim**: several files side by side, scrolled to and highlighting the relevant lines,
without hijacking the screen while the user is reading.

## Goals

- An agent can build a **deck** of numbered **views**, each a layout of up to four
  panes, each pane a file with an optional highlighted line range.
- The agent references views in its prose ("see view 2"); the user opens them **at
  their own pace** via keymaps. Nothing steals focus.
- Agents choose from a **fixed set of approved layouts** — screen space is bounded.
- One portable mechanism for every agent: an Agent Skill (`SKILL.md` + a shell CLI),
  the format Claude Code, Codex and Cursor all load.
- Works identically on **macOS** (current machine) and **Ubuntu/KDE** (laptop), both in
  Ghostty.

## Non-goals

- Showing a file at a git revision that is not checked out (`rev` field). Worktrees on
  disk already cover cross-branch comparison by absolute path. Revisit on demand.
- Per-agent namespaces. Agent vendors do not expose a uniform session identity.
- Re-registering the socket when Neovim `:cd`s after startup.
- Auto-opening views on arrival (explicitly rejected: notify only).

## Decisions and alternatives considered

### Transport

| Option | Verdict |
|---|---|
| **1. Thin CLI → `--remote-expr` RPC → Neovim validates and owns decks** | **Chosen.** Immediate, specific errors back to the agent; CLI needs only bash + nvim; one source of validation logic. |
| 2. Fat CLI building a full JSON payload | Duplicates validation outside Lua; needs `jq`/python; harder quoting. |
| 3. Filesystem drop directory + `vim.uv` fs watcher | No socket, but fs events are unreliable on macOS and the agent never learns whether the deck was accepted. |

### Finding the right Neovim

| Option | Verdict |
|---|---|
| Single fixed socket (`/tmp/nvimsocket`) | Only one Neovim can own it; a second instance collides. |
| Socket keyed on the repo's git common dir | Breaks the actual workflow: Neovim is launched from `~/repos`, which is not a repo. |
| **Socket keyed on Neovim's cwd; CLI walks up from the agent's main checkout** | **Chosen.** See [Socket resolution](#socket-resolution). |

### Grouping views

| Option | Verdict |
|---|---|
| **Decks, one per explanation; newest finished deck owns the hotkeys** | **Chosen.** "View 2" always means view 2 of the explanation being read. |
| One flat list per Neovim | Numbers stop matching prose once a second explanation arrives. |
| Decks per agent namespace | Requires agent identity the vendors don't uniformly expose. |

### On arrival

Notify only (`vim.notify`), never move focus.

## Architecture

### New modules

| Path | Responsibility |
|---|---|
| `lua/custom/show_me/init.lua` | `setup()`: start the socket server on `VimEnter`, keymaps, `:ShowMe` command; `rpc(args)` entry point dispatching CLI subcommands |
| `lua/custom/show_me/deck.lua` | Deck/view/pane types, request validation, JSON persistence and pruning. No window side effects. |
| `lua/custom/show_me/layout.lua` | The four layout builders and their pane-count rules |
| `lua/custom/show_me/render.lua` | The dedicated `show-me` tab: build layout, load buffers, scroll, highlight, winbar |
| `lua/custom/show_me/socket.lua` | Socket directory + path derivation shared by `setup()` and specs |
| `skills/show-me-nvim/SKILL.md` | Agent-facing instructions: when to make a deck, layout choice, how to cite views |
| `skills/show-me-nvim/scripts/show-me` | The CLI (bash 3.2-compatible) |
| `skills/show-me-nvim/install.sh` | Symlinks the skill into `~/.claude/skills`, `~/.codex/skills`, `~/.cursor/skills` |
| `.github/workflows/specs.yml` | Runs `test/run.sh` on `ubuntu-latest` and `macos-latest` |

`init.lua` gains one line calling `require('custom.show_me').setup()`, matching how the
other `custom.*` modules are wired.

### Layouts

Exactly four. Pane order is reading order.

```
single (1)    cols2 (2)     cols3 (3)      main-stack (3 or 4)
┌────────┐   ┌───┬────┐   ┌──┬──┬──┐     ┌─────┬───┐
│   1    │   │ 1 │ 2  │   │1 │2 │3 │     │     │ 2 │
│        │   │   │    │   │  │  │  │     │  1  ├───┤
└────────┘   └───┴────┘   └──┴──┴──┘     │     │ 3 │
                                         └─────┴───┘
```

`main-stack`: pane 1 takes the left ~60% at full height; panes 2..n stack evenly on the
right. Splits are created with explicit `vertical`/`aboveleft`/`belowright` modifiers so
the user's `splitright`/`splitbelow` settings don't change the geometry.

### Data model

Persisted as JSON at `stdpath('state')/show-me/<scope-hash>/<id>.json`. Timestamps are
integer epoch milliseconds.

```lua
---@class ShowMePane
---@field path string      Absolute, resolved path
---@field first? integer   1-based first highlighted line
---@field last? integer    1-based last highlighted line, inclusive

---@class ShowMeView
---@field layout 'single'|'cols2'|'cols3'|'main-stack'
---@field title? string
---@field panes ShowMePane[]

---@class ShowMeDeck
---@field id integer        Monotonic per scope, starting at 1
---@field title string
---@field created_at integer
---@field done boolean      Only done decks are notified and can become current
---@field views ShowMeView[]
```

Only the 10 most recent decks per scope are kept; older files are deleted on each
`deck` call. The **current deck** is the most recently `done` deck, or whichever deck
the user last picked from `<leader>vd`. It's in-memory only; on restart it falls back
to the newest done deck on disk.

## CLI surface

```
show-me deck <title>                                   → stdout: "deck <id>"
show-me view <deck-id> <layout> <pane>... [--title T]  → stdout: "view <n>"
show-me done <deck-id>                                 → stdout: "ok"
show-me status                                         → socket path, scope, current deck
show-me socket                                         → resolved socket path (no RPC)
```

`<pane>` is `path`, `path:N` (highlight line N), or `path:N-M`. Relative paths are
resolved against the CLI's cwd, so `../wt-feature/src/a.py` and absolute paths both
work.

Exit codes: `0` ok, `1` request rejected by Neovim (message on stderr), `2` usage
error, `3` no reachable Neovim (stderr names every socket path tried).

`SHOW_ME_SOCKET=/path` overrides resolution entirely (also how the specs target a
headless instance).

### Typical agent session

```sh
show-me deck "How a login request is authenticated"     # deck 7
show-me view 7 main-stack src/auth.py:40-88 src/token.py:10-30 src/db.py:5-19 --title "Login path"
show-me view 7 cols2 ../repo-wt-feat/src/auth.py:40-90 src/auth.py:40-88 --title "Branch vs main"
show-me done 7
```

Then, in prose: *"The token is minted in `token.py` (view 1, top-right pane)…"*

## Data flow

1. **CLI** parses args, resolves each pane path to an absolute path (`cd … && pwd -P`
   on the directory part), and resolves the socket.
2. **CLI** calls
   `nvim --server <sock> --remote-expr "luaeval(\"require('custom.show_me').rpc(_A)\", [<args>])"`,
   where `<args>` is a Vimscript list of single-quoted strings with embedded `'`
   doubled. This avoids any JSON construction in shell.
3. **`rpc(args)`** dispatches on `args[1]`, calls into `deck.lua` to validate and
   persist, and returns a string: `"ok …"` or `"error: <reason>"`.
4. **CLI** writes the payload after `ok` to stdout and exits 0, or writes the
   message to stderr and exits 1.
5. **On `done`**, Neovim makes the deck current and notifies:
   `show-me: How a login request is authenticated · 2 views · <leader>v1`.
6. **User** presses `<leader>v1`: `render.lua` finds or creates the `show-me` tab,
   closes its windows, builds the layout, and loads each buffer. Then it sets the
   cursor to `first`, puts the range at the top with `zt`, applies a highlight
   extmark (`ShowMeRange`, linked to `Visual` by default), and sets the winbar to
   `2/3 · Login path · auth.py:40-88`.

Panes hold real file buffers: LSP, `gd`, and edits all work as usual.

## Socket resolution

Both sides share one derivation:

```
dir   = /tmp/show-me-<uid>                 (mode 0700; CLI refuses if owned by another user)
path  = <dir>/<first 16 hex of sha256(realpath(scope))>.sock
```

`/tmp` (not `$XDG_RUNTIME_DIR`, which macOS lacks) keeps both machines identical and
the path well under the 104-byte macOS `sun_path` limit.

**Neovim side** (on `VimEnter`): `scope = realpath(cwd)`. If a socket file already
exists at the path, it probes it. A live socket means another Neovim owns the scope, so
this instance logs at DEBUG and doesn't listen. A dead socket is deleted, and then
`serverstart(path)` runs.

**CLI side:** the CLI tries scopes nearest first. It walks from `realpath(cwd)`
up to `/`, then from the repo's **main checkout root** (the parent of
`realpath(git rev-parse --git-common-dir)`) up to `/`, skipping any directory it
has already tried. Inside a linked worktree, that second walk reaches the main
checkout. For each scope it computes the path, and the first socket that answers
`--remote-expr 1` within 2s wins. Dead or suspended sockets are skipped, and the
RPC itself has a 10s deadline, so a Ctrl-Z'd Neovim can't hang the agent.

So an agent in `~/repos/foo` or in any worktree of `foo` reaches the Neovim in
`~/repos`. A Neovim opened directly inside `~/repos/foo` is nearer, so it takes
precedence.

## Portability (macOS + Ubuntu)

- The CLI targets **bash 3.2**: no associative arrays, no `${x,,}`, no `mapfile`. It
  uses `id -u` rather than relying on `$UID`.
- Hashing uses `sha256sum`, falling back to `shasum -a 256`. Paths are resolved with
  `cd … && pwd -P` rather than `realpath` or `readlink -f`. No `sed -i`, and no GNU-only
  flags.
- The Lua side uses only `vim.fn.sha256`, `vim.uv.fs_realpath` and `vim.fn.serverstart`,
  which behave the same on both platforms.
- Hash parity between the CLI and Lua is covered by a spec, and CI runs the specs on
  both OSes.

## Error handling

Each of these is returned to the agent as `error: …`, exit 1:

- Unknown subcommand, or unknown layout. The message lists the four valid layouts.
- Pane count doesn't fit the layout, e.g. `cols2 takes 2 panes, got 3`.
- The file doesn't exist or isn't readable.
- A range is malformed, has `first > last`, or goes past EOF. The message gives the
  file's line count.
- The deck id is unknown, or the deck is already `done` and a `view` is sent to it.
- More than 9 views in a deck, since the keymaps only reach `<leader>v9`.

No reachable Neovim is exit 3, and the message lists every path tried, including any
`SHOW_ME_SOCKET`.

**Sandboxed agents.** Codex's default sandbox, and Claude Code with sandboxing turned
on, may block connecting to unix sockets. `SKILL.md` tells agents that if `show-me`
fails with exit 3 while sandboxed, they should ask for escalation instead of retrying.
The README documents an allowlist entry for each tool.

## User-facing keymaps

| Keys | Action |
|---|---|
| `<leader>v1`…`<leader>v9` | Open view N of the current deck in the `show-me` tab |
| `]v` / `[v` | Next / previous view, only active in the `show-me` tab |
| `<leader>vd` | Picker (snacks) of recent decks; picking one makes it current and opens view 1 |
| `<leader>vq` | Close the `show-me` tab |

`:ShowMe [n]` mirrors `<leader>vN`, and `:ShowMe` with no argument opens the picker.
The `<leader>v` prefix is currently unused.

## Agent skill (`SKILL.md`) content outline

- **When to use:** when explaining code that spans more than one location, or when
  the user asks to be shown something. Not for a single short snippet that reads fine
  inline.
- **Workflow:** `deck` → one `view` per illustration → `done` → prose that cites
  `view N` and the pane position.
- **Layout guide:**
  - `single`: one focus.
  - `cols2`: compare or contrast, or caller and callee.
  - `cols3`: a pipeline of three stages.
  - `main-stack`: one primary file plus its helpers.
- **Range guidance:** keep ranges to roughly 60 lines, enough to fit a pane, and
  prefer one view per idea over packing panes.
- **Rules:** don't send `done` until all views are added. Don't re-send a deck to
  "refresh" it. On exit 3 under a sandbox, request escalation.

## Testing

Specs live in `test/spec/` and use the existing `test/helpers.lua` and `test/run.sh`:

- `show_me_deck_spec.lua`: validation for every error case listed above, id
  monotonicity, pruning to 10, persistence round-trip, and current-deck selection.
- `show_me_layout_spec.lua`: run headless, it builds each layout and asserts the
  `vim.fn.winlayout()` tree shape and pane order.
- `show_me_cli_spec.lua`: starts `nvim --headless --listen <tmp-sock>`, runs the real
  `show-me` script against it with `SHOW_ME_SOCKET`, and asserts stdout, stderr and
  exit codes for a full deck/view/done session and for the rejection paths. It also
  checks that `show-me socket` and `socket.lua` produce the same path for the same
  scope, and that ancestor walking finds a socket registered for a parent directory.

CI uses `.github/workflows/specs.yml`, with a matrix of `ubuntu-latest` and
`macos-latest`. It installs stable nvim and runs `./test/run.sh show_me`.

## Documentation

- **README:** a "show-me" section covering what it is, `install.sh`, the keymaps, and
  the sandbox and allowlist notes for each agent.
- **`CHEATSHEET.md`:** the `<leader>v*` keymaps.
- Module docstrings in each `show_me/*.lua` file, following the style of the existing
  `custom/*.lua` headers.
