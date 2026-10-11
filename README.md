# chance.nvim

A personal Neovim configuration, grown out of
[kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim).

It started as stock kickstart and has drifted a long way since: the picker stack
was migrated to snacks.nvim, treesitter moved to v2, and the config is now built
around a specific way of working — **supervising coding agents rather than typing
most of the code yourself**

That shift is what most of the custom configuration is for. When an agent produces
a branch, the useful unit of navigation stops being the filesystem and starts being
the change set: what changed, what to look at next, where the review threads are.
Neo-tree still owns "where does this file live"; Diffview, Octo and gh-dash own
"what did this branch do".

**`CHEATSHEET.md` is the keymap reference.** This file is just setup.

## What's in it

**Review and agent workflow**
- [diffview.nvim](https://github.com/dlyongemallo/diffview.nvim) — change-set
  review, with base-branch resolution that understands stacked PRs and RC branches
  (see `lua/custom/review.lua`, and the "Choosing a review base" section of the
  cheatsheet)
- [octo.nvim](https://github.com/pwntester/octo.nvim) — GitHub PR review, inline
  comments and threads, without the browser
- [gh-dash](https://github.com/dlvhdr/gh-dash) — terminal PR inbox; config lives in
  `gh-dash/config.yml` in this repo
- [claudecode.nvim](https://github.com/coder/claudecode.nvim) — Claude Code over its
  IDE protocol, so the agent can read editor state and open files here
- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) and
  [unclash.nvim](https://github.com/madmaxieee/unclash.nvim) — hunk-level review and
  merge-conflict resolution

**Editing and navigation**
- [snacks.nvim](https://github.com/folke/snacks.nvim) — picker, notifier, input,
  `vim.ui.select`, terminal, lazygit and a pile of QoL modules. Replaced telescope.
- [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) — file tree
- [auto-session](https://github.com/rmagatti/auto-session) — one session per project
  directory
- [grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim) — find and replace
- [wilder.nvim](https://github.com/gelguy/wilder.nvim) — cmdline completion
- `:E` — `:edit` with fuzzy subsequence path completion, so `:E lua/sna<Tab>`
  resolves `lua/custom/plugins/snacks.lua` (see `lua/custom/fuzzy_edit.lua`)

**Language support**

nvim-lspconfig + mason, nvim-cmp, conform.nvim, nvim-lint, and nvim-treesitter on
`main` (v2). See the cheatsheet for per-language coverage.

## Installation

### Install Neovim

This configuration expects **Neovim 0.12.0 or later** (latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) or
['nightly'](https://github.com/neovim/neovim/releases/tag/nightly)), which is
required by [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
on its default `main` branch. If you are experiencing issues, upgrade Neovim
first.

### Install External Dependencies

Core:
- Basic utils: `git`, `make`, `unzip`, `tar`, `curl`, C Compiler (`gcc`)
- [`tree-sitter` CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md)
  **0.26.1 or later** from your OS package manager (not via `npm`), required to
  compile parsers for nvim-treesitter
- [ripgrep](https://github.com/BurntSushi/ripgrep#installation)
- Clipboard tool (xclip/xsel/win32yank or other depending on the platform)
- A [Nerd Font](https://www.nerdfonts.com/): optional, provides various icons
  - if you have it set `vim.g.have_nerd_font` in `init.lua` to true
- Emoji fonts (Ubuntu only, and only if you want emoji!) `sudo apt install fonts-noto-color-emoji`

Required by the review workflow:
- **[`gh`](https://cli.github.com/), authenticated** — `gh auth login`. Octo and
  the review-base resolution both go through it.
  - Optional: `gh auth refresh -s read:project` if you want Octo's Projects v2
    fields. Everything else works without that scope.
- **[`gh dash`](https://github.com/dlvhdr/gh-dash)** — `gh extension install dlvhdr/gh-dash`
- **[`lazygit`](https://github.com/jesseduffield/lazygit)** — used by the snacks
  lazygit keymaps (`Space gg`)
- **[Claude Code CLI](https://claude.com/claude-code)** — for claudecode.nvim
- **[`linear`](https://github.com/schpet/linear-cli)** — for the Linear integration
  (`Space l*`). Optional: everything else works without it, and the config degrades
  to a single notification if it's missing. See Linear setup below.

Language Setup:
- If you want to write Typescript, you need `npm`
- If you want to write Golang, you will need `go`
- etc.

> [!NOTE]
> See [Install Recipes](#Install-Recipes) for additional Windows and Linux specific notes
> and quick install snippets

### Set Up on a New Machine

> [!NOTE]
> Back up any existing configuration first. That means your existing `init.lua`
> and the Neovim state in `~/.local/share/nvim/`.

**1. Clone the repo** somewhere you keep code, and symlink it into place. Cloning
directly into `~/.config/nvim` also works, but the symlink keeps the checkout
alongside your other repos and makes the gh-dash step below read naturally.

```sh
git clone git@github.com:chanceygardener/kickstart.nvim.git ~/repos/chance.nvim
ln -s ~/repos/chance.nvim "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim
```

On Windows the config path is `%localappdata%\nvim\` (cmd) or
`$env:LOCALAPPDATA\nvim\` (powershell).

**2. Link the gh-dash config**, so the PR inbox has the same sections and
keybindings everywhere:

```sh
mkdir -p ~/.config/gh-dash
ln -s ~/repos/chance.nvim/gh-dash/config.yml ~/.config/gh-dash/config.yml
```

`repoPaths` in that file is a glob (`"*": ~/repos/*`) rather than a list of
absolute paths, specifically so it stays portable across machines. If you keep
checkouts somewhere other than `~/repos`, that's the one line to change.

**3. Authenticate `gh`** — the review workflow depends on it:

```sh
gh auth login
gh extension install dlvhdr/gh-dash
```

**4. Start Neovim.** lazy.nvim installs everything on first launch; `:Lazy` shows
the status. Mason then installs language servers and formatters in the background —
`:Mason` shows progress. Treesitter compiles parsers on first use.

```sh
nvim
```

**5. Check it worked** with `:checkhealth`, then read `CHEATSHEET.md`.

### Linear setup

Optional, and separate from the steps above because it needs an account. Skip it
and everything except the `Space l*` keys works normally.

```sh
brew install schpet/tap/linear
linear auth login          # API key from linear.app/settings/account/security
cd <repo> && linear config # optional — sets this repo's default team
```

`linear config` is genuinely optional: `Space ls` searches every team and needs no
configured team. It's only required for `Space lS` (team-scoped search) and for the
bare-number form (`linear issue view 123`).

Then `Space lt` on a branch with an open PR. No Neovim config changes are needed —
the integration detects the CLI at runtime.

To work on the integration without a Linear account, see `test/README.md`, which
documents stub `linear` and `gh` binaries that reproduce the real output shapes.

### show-me: agents point at code

Terminal agents (Claude Code, Codex, Cursor) can show code in this Neovim while
they explain it. An agent builds a *deck* of numbered views and you open them as
you read. Each view uses one of four layouts (`single`, `cols2`, `cols3`,
`main-stack`), and each pane is a file with a highlighted range. Nothing ever
pops up uninvited; you get a notification.

**Install the skill** once per machine. This links it into `~/.claude/skills`,
`~/.codex/skills` and `~/.cursor/skills`, and puts the CLI at
`~/.local/bin/show-me`:

```sh
./skills/show-me-nvim/install.sh
```

**How agents find this Neovim:** on startup it listens on
`/tmp/show-me-<uid>/<hash of cwd>.sock`. The CLI walks up from the agent's main
checkout (worktrees map to their main checkout) and uses the first socket that
answers, so an agent anywhere under `~/repos` reaches a Neovim started in
`~/repos`. `show-me status` shows what it found, and `SHOW_ME_SOCKET` overrides
it.

| Keys | Action |
|---|---|
| `Space v1`…`Space v9` | Open view N of the current deck |
| `]v` / `[v` | Next / previous view (in the show-me tab) |
| `Space vd` | Pick a recent deck |
| `Space vq` | Close the show-me tab |

**Sandboxed agents.** `show-me` connects to a unix socket, which agent sandboxes
may block. Allow it explicitly:

- Claude Code: add `"Bash(show-me:*)"` to `permissions.allow`. If sandboxing is
  on, also list it in `sandbox.excludedCommands`.
- Codex: approve `show-me` when prompted, or run with a sandbox mode that allows
  local sockets.
- Cursor: add `show-me` to the terminal command allowlist.

### Layout

```
init.lua                    most plugin specs and all core settings
lua/kickstart/plugins/      kickstart's optional modules, enabled from init.lua
lua/custom/plugins/         personal plugin specs — auto-imported, one file each
lua/custom/git.lua          git primitives shared by the modules below
lua/custom/repo.lua         which repo a buffer belongs to (buffer-relative)
lua/custom/work.lua         story context: a ticket plus all open PRs implementing it
lua/custom/review.lua       review-base resolution shared by the diff entry points
lua/custom/linear.lua       Linear issue view and search, over the `linear` CLI
lua/custom/fuzzy_edit.lua   the `:E` command
lua/custom/show_me/         show-me: agent-built views, the socket agents reach it by
skills/show-me-nvim/        the show-me agent skill: SKILL.md, the CLI, install.sh
gh-dash/config.yml          gh-dash config, symlinked to ~/.config/gh-dash/
test/stub/                  fake `linear` and `gh` for offline testing
CHEATSHEET.md               keymap reference
```

`work.lua` is the shared resolver, and it is anchored on the **ticket** rather than
a repo: a story is a Linear ticket plus every open PR implementing it, discovered
with one `gh search prs` scoped to the org derived from the current repo's remote.
`review.lua` takes its diff base from the story's PR for whichever repo the current
buffer is in. Because work spans several repos with no monorepo, nothing resolves
against Neovim's cwd — `repo.lua` answers "which repo is this buffer in" and every
git call is made against that path.

Run `./test/run.sh` to exercise all of it offline; see `test/README.md`.

`init.lua` ends with `{ import = 'custom.plugins' }`, so **a new file dropped in
`lua/custom/plugins/` is picked up automatically** — no `init.lua` edit needed.
Small specs go in `lua/custom/plugins/init.lua`; anything with real configuration
gets its own file.

This repo **tracks `lazy-lock.json` in git** so every machine installs the same
plugin commits — lazy.nvim
[recommends a lockfile in version control](https://lazy.folke.io/usage/lockfile).
Commit it when you add or update a plugin. Note that upstream kickstart gitignores
it, so merging from upstream may surface that conflict.

### Credits

Forked from [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim), which
remains the best starting point if you want to build your own config from scratch.
[The Only Video You Need to Get Started with Neovim](https://youtu.be/m8C0Cq9Uv9o)
is a good introduction to it.

### Install Recipes

Below you can find OS specific install instructions for Neovim and dependencies.

After installing all the dependencies continue with the
[Set Up on a New Machine](#set-up-on-a-new-machine) step.

#### Windows Installation

<details><summary>Windows with Microsoft C++ Build Tools and CMake</summary>
Installation may require installing build tools and updating the run command for `telescope-fzf-native`

See `telescope-fzf-native` documentation for [more details](https://github.com/nvim-telescope/telescope-fzf-native.nvim#installation)

This requires:

- Install CMake and the Microsoft C++ Build Tools on Windows

```lua
{'nvim-telescope/telescope-fzf-native.nvim', build = 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release && cmake --install build --prefix build' }
```
</details>
<details><summary>Windows with gcc/make using chocolatey</summary>
Alternatively, one can install gcc and make which don't require changing the config,
the easiest way is to use choco:

1. install [chocolatey](https://chocolatey.org/install)
either follow the instructions on the page or use winget,
run in cmd as **admin**:
```
winget install --accept-source-agreements chocolatey.chocolatey
```

2. install all requirements using choco, exit the previous cmd and
open a new one so that choco path is set, and run in cmd as **admin**:
```
choco install -y neovim git ripgrep wget fd unzip gzip mingw make
```
</details>
<details><summary>WSL (Windows Subsystem for Linux)</summary>

```
wsl --install
wsl
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep unzip git xclip neovim
```
</details>

#### Linux Install
<details><summary>Ubuntu Install Steps</summary>

```
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep unzip git xclip neovim
```
</details>
<details><summary>Debian Install Steps</summary>

```
sudo apt update
sudo apt install make gcc ripgrep unzip git xclip curl

# Now we install nvim
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo rm -rf /opt/nvim-linux-x86_64
sudo mkdir -p /opt/nvim-linux-x86_64
sudo chmod a+rX /opt/nvim-linux-x86_64
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz

# make it available in /usr/local/bin, distro installs to /usr/bin
sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/
```
</details>
<details><summary>Fedora Install Steps</summary>

```
sudo dnf install -y gcc make git ripgrep fd-find unzip neovim
```
</details>

<details><summary>Arch Install Steps</summary>

```
sudo pacman -S --noconfirm --needed gcc make git ripgrep fd unzip neovim
```
</details>

