# Multi-Repo Work Context — Design

**Date:** 2026-09-10
**Status:** approved, not yet implemented

## Problem

The work-context and Linear integration currently in `lua/custom/` assumes one repo
per Neovim instance. Every git lookup runs in Neovim's **cwd**, and context is
modelled as *one repo's* branch → PR → ticket.

That assumption does not hold. Work happens across roughly four repos — there is no
monorepo — and a single story frequently touches several of them. Neovim is
launched from `~/repos`, the parent directory holding all the checkouts.

Measured consequences of running from `~/repos` today:

```
cwd             = /Users/chanceygardener/repos
git.root()      = nil
git.cache_key() = nil
work.peek()     = nil
```

Everything returns nil — not just the Linear ticket, but the diff base too. Opening
a file from inside a repo does not help, because `git.root()` still runs git in the
cwd rather than the buffer's directory.

Secondarily, even with that fixed, per-repo context answers the wrong question. The
useful unit is the **story**: ENG-1934 may have PRs in three repos, and a PR stack
means several PRs in one repo for the same ticket.

## Goals

- Work correctly with Neovim launched from `~/repos` (or anywhere else).
- Treat the **ticket** as the unit of context, with its PRs across repos.
- Switch between stories quickly, by ticket, because reviewing one PR stack while
  another implementation runs is routine.
- Keep the statusline free of subprocesses and network calls.

## Non-goals

Deliberately excluded, each a real feature that is not needed to re-point and keep
working:

- Per-tab contexts.
- Saving or restoring window layout per story (overlaps auto-session).
- Any notion of a configured repo list or workspace file.
- Discovering work that has no PR yet.

## Design

### Two shifts

**1. Path-aware instead of cwd-aware.** `custom.git` takes an optional directory and
runs `git -C <dir>`. A new `custom.repo` answers "which repo does this buffer belong
to?" from the buffer's path.

**2. Ticket-anchored instead of repo-anchored.** Context is a sticky ticket plus the
set of PRs implementing it.

### Modules

| Module | Role | Change |
|---|---|---|
| `custom.git` | git primitives | add optional dir arg → `git -C <dir>` |
| `custom.repo` | buffer path → `{ root, name, owner, branch }` | **new**, cached per directory |
| `custom.work` | sticky ticket + PRs across repos, switching, story picker | restructured |
| `custom.linear` | issue view / issue search | unchanged |
| `custom.review` | diff base | reads `active.base`, adds `-C<root>` |

### State

One global context at a time:

```lua
{
  issue = 'ENG-1934',
  title = 'Retry failed ingestion requests',
  prs = {
    { repo = 'kgrisk',       number = 12, base = 'main',    url = '…', root = '/Users/…/repos/kgrisk' },
    { repo = 'kgloader',     number = 47, base = 'main',    url = '…', root = '/Users/…/repos/kgloader' },
    { repo = 'kg-assistant', number =  8, base = 'rc/2.4',  url = '…', root = nil },  -- not cloned
  },
  active = <the prs entry whose root contains the current buffer, or nil>,
  searched_at = 1757500000000,  -- integer ms since epoch, per CLAUDE.md
}
```

`issue`, `title` and `prs` are sticky until the story is switched. `active` is
recomputed per buffer from a cached path lookup — **no subprocess** — which is what
keeps the statusline free.

Resolved contexts are cached per ticket, so switching back to a previous story is
instant.

### Resolution

```
open a buffer ──▶ custom.repo: which repo is this file in?
                       │
                       ├─ ticket already sticky? ──▶ recompute `active` only
                       │
                       └─ no ticket yet
                              │
                              ├─ gh pr view -R <owner/repo> --json number,title,baseRefName,url
                              │       parse [ENG-1934] from the title  (authoritative)
                              │       fall back to `linear issue id`   (pre-PR only)
                              │
                              └─ gh search prs '[ENG-1934]' --owner <derived> --state open
                                        --json number,title,url,repository
                                             │
                                     all PRs for the story, one call
```

**Owner derivation.** Read off the current repo's remote (`git@github.com:acme/kgrisk.git`
→ `acme`). No configuration. Work repos share one org; if that ever stops being
true, the call site takes a list and adding a second owner is a one-line change.

**Repo → disk mapping.** For each discovered PR, look for `<parent-of-current-root>/<repo-name>`
and confirm its `origin` remote matches `owner/repo`. The remote check is what stops
a coincidentally-named sibling directory from being adopted. An unmatched repo keeps
`root = nil` and is shown as not cloned.

**Ticket parsing** is unchanged and already implemented: `[A-Za-z][A-Za-z0-9]*-%d+`,
brackets optional, uppercased, team key never assumed. PR title wins over branch
name on disagreement, and the conflict is recorded.

### Switching

`<leader>lw` opens a picker whose rows are **stories, not PRs**. PRs are grouped by
the ticket parsed from their titles, so a PR stack collapses into a single row:

```
● ENG-1934  Retry failed ingestion         3 PRs   mine
  ENG-2201  Backoff resets incorrectly     1 PR    mine
  DATA-441  Duplicate rows after restart   2 PRs   review requested
  ENG-1800  Migrate the loader             1 PR    recent
```

Merged from three sources, all cheap and needing no configuration:

- `gh search prs --author=@me --state=open --owner <derived>`
- `gh search prs --review-requested=@me --state=open --owner <derived>`
- tickets used earlier in the session (in-memory)

Preview lazily renders the Linear issue via `linear issue view`, reusing the
existing `Snacks.picker.preview.cmd` approach. Enter switches.

`:WorkSwitch ENG-1934` switches directly when the ticket is already known.

**A switch re-points `issue`, `prs`, the diff base and the statusline. Buffers and
windows are untouched.** If the new story has no PR in the repo currently being
edited, `active` is nil and the diff commands say so rather than silently diffing
against a wrong base.

### Keymaps and commands

| Key | Action |
|---|---|
| `<leader>lw` | Switch story (picker) |
| `<leader>lc` | Show the current story — lists its PRs; Enter opens that repo's diff |
| `<leader>lt` | View the current story's Linear ticket |
| `<leader>lv` | View any issue (prompt) — unchanged |
| `<leader>ls` / `<leader>lS` | Search all teams / this team — unchanged |
| `<leader>lo` | Open current ticket in browser — unchanged |
| `<leader>lr` | Re-resolve and re-search — unchanged |

`:LinearView` · `:LinearSearch` · `:LinearCurrent` · `:WorkContext` ·
`:WorkContextRefresh` · `:WorkSwitch [TICKET]`

`<leader>lc` absorbs the PR-jumping originally floated as a separate `<leader>lp`:
one key that both shows the story and gets you into any of its repos.

### Diffs across repos

`review.lua` takes its base from `active.base` and passes `-C<root>` to Diffview.
The flag is verified present in diffview's own help file (`diffview.txt`, under
`DiffviewOpen` options: "Run as if git was started in {path} instead of the current
working directory"). So `<leader>dr` diffs the repo of the current buffer even when
cwd is `~/repos`, with no directory change and no `:tcd`.

The story picker in `<leader>lw` is built in `custom.work` with `Snacks.picker`
directly, following the precedent of `review.pick_base`. `custom.linear` keeps
owning issue *content* — view and search — and is not modified by this work beyond
being called for the picker preview.

### Statusline

`ENG-1934 · #12` inside one of the story's repos; `ENG-1934 · 3 PRs` outside them;
blank until the first resolve. Cache-only, asserted by a test that counts
subprocesses across repeated renders.

## Error handling

| Condition | Behavior |
|---|---|
| cwd not a repo (`~/repos`) | Normal — resolution is buffer-relative |
| Buffer outside every story repo | Ticket stays; `active` nil; statusline shows the PR count |
| Story repo not cloned | Listed and marked in `<leader>lc`; Enter explains rather than failing |
| Repo with work but no PR | Not discoverable by `gh search prs`; work proceeds, it is simply unlisted |
| GitHub search index lag | `<leader>lr` re-searches; `<leader>lc` shows search age from `searched_at` |
| No ticket resolvable | `<leader>lw` and `<leader>lv` still work; nothing is fabricated |
| `gh` / `linear` absent | One clear notification each, as already implemented |

## Testing

The existing stubs in `test/stub/` extend naturally, so none of this needs a real
Linear or GitHub.

- `test/stub/gh` gains `search prs`, returning a payload spanning multiple repos and
  multiple tickets, including one repo absent from disk.
- New cases: grouping PRs by ticket, PR stack collapsing to one row, `active`
  selected by buffer path, switching and switching back, not-cloned handling,
  `-C<root>` present in the Diffview command.
- Retained assertions: `peek()` issues zero subprocesses; PR title beats branch name
  and records the conflict; `--all-teams` on `<leader>ls` and not on `<leader>lS`.
- Full regression sweep of the review workflow, which shares `custom.git` and now
  takes its base from `custom.work`.

Fixture for the multi-repo case: this machine's `~/repos` holds 20+ mostly unrelated
checkouts, which is a useful adversarial case — it must not treat siblings as part of
a story without a remote match.

## Known limitations

**`gh search prs` only finds PRs.** A repo where work has started but no PR is pushed
will not appear in the story. Acceptable: the sticky ticket means you can work there
normally, it just is not listed until the PR exists.

**GitHub's search index lags.** A PR opened seconds ago may not appear immediately.
Mitigated by showing search age and offering an explicit re-search.

**Owner is derived from one repo.** If a story ever spans GitHub orgs, PRs outside
the derived owner are silently missed. The call site takes a list specifically so
this becomes a one-line fix, but it is a silent failure until noticed.
