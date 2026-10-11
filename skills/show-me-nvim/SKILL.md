---
name: show-me-nvim
description: Show code in the user's Neovim while explaining it. Use when answering questions about a codebase where the explanation spans more than one location (call chains, data flow, before/after, two branches), or when the user asks to be shown, pointed at, or walked through code. Builds a deck of numbered multi-pane views the user opens at their own pace.
---

# show-me-nvim

The user reads your explanation in the terminal and has Neovim open in another
window. With `show-me` you prepare **views** in Neovim (files side by side,
scrolled to and highlighting the lines you mean) and refer to them in your
answer. Nothing pops up: the user gets a notification and opens each view
with `<leader>v1`…`<leader>v9` as they read.

Run `show-me` from the repository you are discussing. If it is not on `PATH`,
use `scripts/show-me` in this skill's directory.

## When to use it

- The explanation touches **two or more locations**: a caller and its callee, a
  pipeline, a type and where it's built, the same function on two branches.
- The user says "show me", "point me to", "walk me through", "where is".

Skip it for a single short snippet you can quote inline, or when no repository
is involved.

## Workflow

1. `show-me deck "<what this explanation is about>"`: prints `deck <id>`.
2. One `show-me view <id> <layout> <pane>... --title "<short caption>"` per
   illustration. Each call prints `view <n>`, and those numbers are what you cite.
3. `show-me done <id>`. The user is notified only now, so send it after the
   last view and before you write your answer.
4. In your answer, cite views by number and pane position: *"the token is
   minted in `mint()` (**view 1**, top-right pane)…"* Start the answer with
   one line telling the user that views are ready (for example
   "Views 1–3 are ready in Neovim: `<leader>v1`").

## Panes

`path`, `path:N` (highlight line N), or `path:N-M`. Paths are relative to your
working directory or absolute. A path into another worktree (`../repo-feature/src/x.py`)
works, which is how you compare branches.

Keep ranges to **about 60 lines or fewer** so they fit in a pane. Highlight
the lines that matter, not the whole file.

## Layouts

Only these four exist:

| Layout | Panes | Use for |
|---|---|---|
| `single` | 1 | one focal piece of code |
| `cols2` | 2 | compare/contrast; caller and callee; before and after |
| `cols3` | 3 | a three-stage pipeline, read left to right |
| `main-stack` | 3-4 | one primary file (left, wide) plus 2-3 helpers stacked on the right |

Pane 1 is always left (and top-left in `main-stack`); the rest follow in
reading order. Prefer **one idea per view** and more views over packed panes.
A deck holds at most 9 views.

## Example

```sh
show-me deck "How a login request is authenticated"            # deck 4
show-me view 4 main-stack src/auth.py:40-88 src/token.py:10-30 src/db.py:5-19 --title "Login path"
show-me view 4 cols2 ../app-feature/src/auth.py:40-90 src/auth.py:40-88 --title "Feature branch vs main"
show-me done 4
```

## Errors

| Exit | Meaning | What to do |
|---|---|---|
| 1 | Request rejected; stderr says why (bad layout, pane count, missing file, range past end of file) | Fix that view and resend it. Earlier views in the deck are kept |
| 2 | Usage error | Check the argument order above |
| 3 | No Neovim reachable | If you are sandboxed, ask the user to approve running `show-me` outside the sandbox. Otherwise tell the user that their Neovim isn't serving this directory, and continue the explanation without views |

Never send `done` twice, and never rebuild a deck to "refresh" it. If you need
different views, start a new deck.
