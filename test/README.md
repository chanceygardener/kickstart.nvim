# Test stubs

Fake `linear` and `gh` binaries, so the Linear and work-context integrations can be
exercised without a Linear account and without depending on whatever PR happens to
be open.

Put them first on `PATH`:

```sh
PATH="$PWD/test/stub:$PATH" nvim
```

## `linear`

Mimics [`schpet/linear-cli`](https://github.com/schpet/linear-cli) v2.6.0. The
output shapes are taken from that version's source rather than invented:

- `issue view <id>` prints **raw markdown**, because the real CLI only renders ANSI
  and pages when stdout is a TTY — which it never is under `vim.system`
- `issue query --search … --json` prints `{ nodes, pageInfo, totalCount }`, where
  nodes carry `identifier` / `title` / `url` / `state` / `assignee` / `team` and
  deliberately **no description** — which is why the picker preview has to fetch
  per selection instead of up front
- `issue id` prints the branch's identifier, or exits non-zero

Search results span two team keys (`ENG` and `DATA`) on purpose, so the
`--all-teams` default and the team column are actually exercised.

| Variable | Effect |
|---|---|
| `LINEAR_STUB_AUTH_FAIL=1` | every call fails as if unauthenticated |
| `LINEAR_STUB_NO_ISSUE=1` | `issue id` finds nothing (the pre-PR case) |
| `LINEAR_STUB_BAD_JSON=1` | `issue query` emits malformed JSON |
| `LINEAR_STUB_ARGV=<path>` | append each invocation's argv, for assertions |

Viewing `ENG-9999` returns a not-found error, for exercising that path.

## `gh`

**Inert by default** — with no `GH_STUB_*` variable set it execs the real `gh`, so
putting this directory on `PATH` for a Linear test doesn't silently fake GitHub too.
It only ever intercepts `gh pr view --json …` and `gh search prs` (when activated).

| Variable | Effect |
|---|---|
| `GH_STUB_PR_TITLE=<title>` | simulate an open PR with this title |
| `GH_STUB_PR_NUMBER=<n>` | PR number (default 842) |
| `GH_STUB_PR_BASE=<branch>` | base branch (default `main`) |
| `GH_STUB_NO_PR=1` | simulate no open PR (exit 1, as real `gh` does) |
| `GH_STUB_SEARCH=1` | `search prs` returns a fixed multi-repo, multi-ticket payload |
| `GH_STUB_ARGV=<path>` | append each intercepted invocation's argv, for assertions |

The search fixture contains a two-PR stack in one repo, a second repo, a repo that
is deliberately absent from disk, and an unrelated ticket — so grouping, stacking,
and the not-cloned path are all exercised.

## Cases worth re-running after changes

The interesting one is **disagreement**: the branch implies one ticket while the PR
title says another. The PR title must win, since it's the convention that's actually
maintained, and the conflict must be recorded rather than dropped.

```sh
# PR wins, conflict recorded
PATH="$PWD/test/stub:$PATH" GH_STUB_PR_TITLE='[ENG-245] do some work' \
  nvim --headless -c 'lua print(vim.inspect(require("custom.work").get()))' -c 'qa!'

# no ticket in the PR title -> falls back to the branch
PATH="$PWD/test/stub:$PATH" GH_STUB_PR_TITLE='fix a thing' \
  nvim --headless -c 'lua print(vim.inspect(require("custom.work").get()))' -c 'qa!'

# pre-PR: no PR at all, branch tier only
PATH="$PWD/test/stub:$PATH" GH_STUB_NO_PR=1 \
  nvim --headless -c 'lua print(vim.inspect(require("custom.work").get()))' -c 'qa!'

# --all-teams is passed by <leader>ls and omitted by <leader>lS
LINEAR_STUB_ARGV=/tmp/argv PATH="$PWD/test/stub:$PATH" \
  nvim --headless -c 'lua require("custom.linear").search("x")' -c 'sleep 1' -c 'qa!' \
  && cat /tmp/argv
```

`peek()` must never shell out — it runs on every statusline redraw:

```sh
nvim --headless -c 'lua
  local w = require("custom.work")
  local n, real = 0, vim.system
  vim.system = function(...) n = n + 1 return real(...) end
  for _ = 1, 50 do w.peek(); w.statusline() end
  print("subprocesses:", n)  -- must be 0
' -c 'qa!'
```
