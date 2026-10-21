# Review

[README](../README.md) · [Working in the hub](working.md) · [Keys](keys.md#review-tuicr) ·
[Orchestrators](orchestrators.md)

- [The review options](#the-review-options)
- [Review by turn](#review-by-turn)
- [Modes: turns and commits](#modes-turns-and-commits)
- [New turns](#new-turns)
- [Review with lazygit](#review-with-lazygit)
  - [The patch in lazygit](#the-patch-in-lazygit)
- [Files](#files)
- [Hide review](#hide-review)

## The review options

The review column (right) has three choices. They do not depend on each other.

| Choice | Options | How to change | When it applies |
|---|---|---|---|
| What you review (the mode) | **turns** (default): the agent's work, one commit per turn. **commits**: the branch's own commits | `t` in review | at once; it stays for the next picks |
| The program in the review column | **tuicr** (default) or **lazygit** | `JAY_REVIEW=tuicr\|lazygit` in `~/.config/jay/config` | at the next hub start (Ctrl g, Ctrl q, then `jay`) |
| How lazygit draws the patch (lazygit only) | **delta** (default), **difft** or **plain** | `JAY_REVIEW_DIFF=delta\|difft\|plain` in `~/.config/jay/config`; `\|` in lazygit cycles them for now | at the next start of lazygit in the pane (a pick, `t` or `q`) |

`e` in review opens [files](#files) (yazi) over review with either program, and Ctrl g `v`
[hides review](#hide-review).

### tuicr or lazygit

| | tuicr (default) | lazygit (`JAY_REVIEW=lazygit`) |
|---|---|---|
| Good for | reading a turn and writing review comments for the agent | git actions: stage, commit, rebase (commits mode) |
| Review comments | yes | no |
| Turns | the range `base..head` of the turn chain; `(` goes to the newest turn, again for all turns | a view repo with one row per turn (see [Review with lazygit](#review-with-lazygit)) |
| Commits mode | the branch's own commits, read only | lazygit on the worktree itself, with all its git actions |
| A new turn | tuicr starts again on the newest turn | the new row comes in; your place stays |
| The patch | tuicr's own | the hub's renderers: `JAY_REVIEW_DIFF` (see [The patch in lazygit](#the-patch-in-lazygit)) |
| Needs | tuicr 0.27+ | lazygit 0.66+ and delta (`brew install lazygit git-delta`); difftastic for `difft` |
| Keys | [Review (tuicr)](keys.md#review-tuicr) | [Review (lazygit)](keys.md#review-lazygit-jay_reviewlazygit) |

`t`, `e` and `q` do the same in both: `t` toggles the mode, `e` opens files, `q` goes back to
the start (the picker, or the newest turn).

### The patch renderers (lazygit only)

| `JAY_REVIEW_DIFF` | What it shows | Needs |
|---|---|---|
| `delta` (default) | one column of line numbers, a bar on each file (`3/8`, status, path), a line on each hunk (`path:line`, `2/3`), long lines wrapped under the code; `n`/`N` and `l`/`h` jump by file and hunk when the patch has the focus | delta |
| `difft` | a diff of the syntax (difftastic): a reformat or a moved argument shows as what it is; two number columns | difftastic |
| `plain` | delta alone: no wrap (`H` / `L` scroll to the side) | delta |

Without delta or difftastic, the renderer shows git's plain diff under a red line that names
the missing program. tuicr does not use these renderers.

## Review by turn

The hooks of `jay-snapshot` (UserPromptSubmit, Stop, PostToolUse) save the worktree at
each turn as a hidden commit chain per agent: `refs/wt-turns/<id>/base` and
`refs/wt-turns/<id>/head`. They never touch the branch, the index or the files.

- The base is `HEAD` at the agent's first snapshot.
- Each Stop adds a commit `turn · <prompt>`, with the agent's result line as its body.
- Each UserPromptSubmit adds a commit `between turns · edits made outside the agent` when you
  changed files between two turns.
- A turn with no change adds no commit.
- While a turn runs, `refs/wt-turns/<id>/live` holds the turn so far: a commit
  `turn, running · <prompt>` on top of the head. PostToolUse on `Edit`, `MultiEdit`, `Write`,
  `NotebookEdit` and `Bash` replaces it, at most once in 5 s. Stop removes it. The chain keeps
  one commit per turn.
- A turn that ended without Stop (you stopped it) still gets its commit `turn · <prompt>`, at
  the next prompt.
- An agent that goes into another worktree of the repo (`EnterWorktree`, `ExitWorktree`) keeps
  its chain. After the tool (PostToolUse), the turn's changes so far get a commit
  `turn, in <old folder> · <prompt>`, then a commit `worktree · <new folder>` takes the files of
  the new worktree. Thus the next turn shows only its own changes.
  `~/.local/state/jay/turns/<id>.worktree` follows the agent.
- `<id>` is the background agent's short id, else the first 8 characters of the session id. A
  background agent keeps its chain after a resume or `/clear`.
- The refs keep the name `refs/wt-turns` from before the rename to jay: they live in each repo,
  and a new name would lose the old chains.

By hand: `tuicr -r <turn>~1..<turn>` reviews one turn, `tuicr -r refs/wt-turns/<id>/base..refs/wt-turns/<id>/head`
all of them, and `jay snapshot --list [path]` lists the chains of a worktree.

## Modes: turns and commits

Review has two modes. The pane title starts with the mode, and `t` in tuicr toggles it. The mode
stays for the next picks (`~/.local/state/jay/review.mode`).

- **turns**: the picked agent's chain. A worktree pick opens the newest chain of that worktree.
  With no chain, tuicr's own picker opens. A chain opens on its newest turn (the pane types `(`
  into tuicr). While the agent works, that is the running turn. Press `(` to see all turns.
- **commits**: the branch's own commits, from its merge-base with `origin/HEAD` (else `main`,
  else `master`) up to `HEAD`. A branch with no commits of its own opens tuicr's picker.

## New turns

New turns come in by themselves. The pane looks at the chain head every 2 s (commits mode: at
`HEAD`). When it moves, tuicr starts again on the newest turn. It does not do this while you type
a comment or a `:` or `/` prompt; it waits until tuicr is back in NORMAL or SELECT mode. This
also works over tuicr's picker: when an agent's first turn (or running turn) comes, its chain
opens. A running turn that changes does not start tuicr again, so you keep your place: `q`
shows its newest state, and the end of the turn starts tuicr again.

`q` in tuicr means "back": tuicr starts again at its start (the picker, or the newest turn).
When tuicr quits less than 2 s after its start, the pane says so and waits for Enter.

The list's keys act in the list only. The list has no key for review's mode or for files.

## Review with lazygit

`JAY_REVIEW=lazygit` in `~/.config/jay/config` puts lazygit (0.66 or newer) in the review pane
in place of tuicr. Start the hub again after you change it. The modes and `t`, `e`, `q` stay the
same. lazygit has no review comments: use tuicr when you want to write comments for the agent.
See `notes/lazygit-review.md` for the study.

- **turns**: lazygit cannot open the hidden turn refs, so it runs on a view repo,
  `~/.local/state/jay/lazygit/views/<id>`: a repo of its own that reads your repo's objects.
  Its branch `turns` is the chain head, `turns-base` the base. A turn is one row: a yellow `*`
  marks the turns, a green `*` the history under them. A commit, branch or rebase there changes
  only the view, never your repo. While the agent works, the top row is the running turn
  (`turn, running · <prompt>`, the live ref). An agent with no chain yet gets an empty view
  that fills at its first change. For a worktree pick with no chain, lazygit opens on the
  worktree.
- **commits**: lazygit on the worktree itself, with all its git actions (stage, commit, rebase).
  An agent can work in the same worktree at the same time.

New turns come in without a restart: the pane copies the chain's newest commit (the running
turn, else the head) into the view every 2 s, and lazygit refreshes when the branch moves. Your
place stays. When the newest turn was selected, the new turn is selected (the pane types `<`).
When the running turn changes or ends, its row stays where it is and shows the new state.

lazygit reads your own `config.yml` (theme), then the hub's `~/.config/jay/lazygit/hub.yml`
over it: one tab group, list on top, no author or hash, the hub's diff renderers, and the hub's
`t` and `e`. Its state (recent repos) goes to `~/.local/state/jay/lazygit/state`, not into
yours. `jay snapshot --prune` removes a view with its chain.

### The patch in lazygit

The review column is narrow, so the hub has its own diff renderers (`git.diffRenderers` in
`hub.yml`). `JAY_REVIEW_DIFF` puts one first; `|` in lazygit goes to the next one.

- `delta` (default): `jay-diff` with delta. One column of line numbers (the new line; the
  old one on a removed line, in red). A bar on each file: its place in the diff (`3/8`), the
  status (`M`, `A`, `D`, `R`), the path, `+12 -3`. A line on each hunk: `path:line`, its place
  in the file (`2/3`) and the function. A long line wraps under its own code. With the patch
  focused (`0` or a click), the rendering stays, and `n` / `N` go to the next or previous file,
  `l` / `h` to the next or previous hunk.
- `difft`: `jay-diff` with difftastic in inline mode: a diff of the syntax, so a reformat or
  a moved argument shows as what it is. The same file bar and hunk lines (no line in the hunk
  line), difftastic's two number columns, the same wrap. With the patch focused, lazygit shows
  git's raw diff.
- `plain`: delta alone, without `jay-diff`: one number column, `path:line` on each hunk. Long
  lines do not wrap: they stop at the edge, and `H` / `L` scroll the patch to the side. With the
  patch focused, lazygit shows git's raw diff.

The hub's renderers do not read your `~/.gitconfig` `[delta]` settings, and use 24-bit color.
See `notes/lazygit-review.md` ("7. The diff") and the screen dumps in `notes/lazygit-diff/`.
Keys: [Review (lazygit)](keys.md#review-lazygit-jay_reviewlazygit).

## Files

`e` in tuicr (NORMAL or SELECT mode) opens files: yazi in the review's worktree, over review.
tuicr keeps running under it. `e` or `q` in yazi closes files, and review comes back. A new pick
moves files to the new worktree.

In files:

- `o` opens the hovered file in this pane (yazi's own open).
- `O` opens the hovered file or folder in your editor, in its project, in a new tab (`jay edit`,
  see [Open your editor](working.md#open-your-editor)).
- `W` is yazi's "open with" menu (yazi's own `O`).

## Hide review

Ctrl g `v` hides review, and the agent viewer gets its width. Ctrl g `v` again shows review on
the right, at the width it had. The focus stays in the column that has it. Ctrl g `3` and Enter
on a worktree row also show a hidden review, and move the focus to it.

- tuicr runs on while review is hidden: your place and draft comments stay. New turns come in
  when review shows again.
- Files closes when review hides, and opens again when review shows.
- A fresh hub (`jay` after a quit) starts with review shown.

zellij cannot hide a tiled pane, so a hidden review is a floating pane of no size in the bottom
right corner, and the hub tab's floating panes are hidden. A new floating pane (Ctrl g Tab,
Ctrl g `r`) shows them again; the hub hides them again when that pane closes. Ctrl g `p` `w`
(zellij's floating panes key) shows them too: the list hides them again within 3 s.
