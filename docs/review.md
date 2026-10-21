# Review

[README](../README.md) · [Working in the hub](working.md) · [Keys](keys.md#review-tuicr) ·
[Orchestrators](orchestrators.md)

- [Review by turn](#review-by-turn)
- [Modes: turns and commits](#modes-turns-and-commits)
- [New turns](#new-turns)
- [Review with lazygit](#review-with-lazygit)
  - [The patch in lazygit](#the-patch-in-lazygit)
- [Files](#files)
- [Hide review](#hide-review)

## Review by turn

The hooks of `claude-turn-snapshot` (UserPromptSubmit, Stop, PostToolUse) save the worktree at
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
  the new worktree. Thus the next turn shows only its own changes. `wt-turns/<id>.worktree`
  follows the agent.
- `<id>` is the background agent's short id, else the first 8 characters of the session id. A
  background agent keeps its chain after a resume or `/clear`.

By hand: `tuicr -r <turn>~1..<turn>` reviews one turn, `tuicr -r refs/wt-turns/<id>/base..refs/wt-turns/<id>/head`
all of them, and `claude-turn-snapshot --list [path]` lists the chains of a worktree.

## Modes: turns and commits

Review has two modes. The pane title starts with the mode, and `t` in tuicr toggles it. The mode
stays for the next picks (`~/.local/state/wt-hub-review.mode`).

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

`WT_REVIEW=lazygit` in `~/.config/wt-hub/config` puts lazygit (0.66 or newer) in the review pane
in place of tuicr. Start the hub again after you change it. The modes and `t`, `e`, `q` stay the
same. lazygit has no review comments: use tuicr when you want to write comments for the agent.
See `notes/lazygit-review.md` for the study.

- **turns**: lazygit cannot open the hidden turn refs, so it runs on a view repo,
  `~/.local/state/wt-hub/lazygit/views/<id>`: a repo of its own that reads your repo's objects.
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

lazygit reads your own `config.yml` (theme), then the hub's `~/.config/wt-hub/lazygit/hub.yml`
over it: one tab group, list on top, no author or hash, the hub's diff renderers, and the hub's
`t` and `e`. Its state (recent repos) goes to `~/.local/state/wt-hub/lazygit/state`, not into
yours. `claude-turn-snapshot --prune` removes a view with its chain.

### The patch in lazygit

The review column is narrow, so the hub has its own diff renderers (`git.diffRenderers` in
`hub.yml`). `WT_REVIEW_DIFF` puts one first; `|` in lazygit goes to the next one.

- `delta` (default): `wt-hub-diff` with delta. One column of line numbers (the new line; the
  old one on a removed line, in red). A bar on each file: its place in the diff (`3/8`), the
  status (`M`, `A`, `D`, `R`), the path, `+12 -3`. A line on each hunk: `path:line`, its place
  in the file (`2/3`) and the function. A long line wraps under its own code. With the patch
  focused (`0` or a click), the rendering stays, and `n` / `N` go to the next or previous file,
  `l` / `h` to the next or previous hunk.
- `difft`: `wt-hub-diff` with difftastic in inline mode: a diff of the syntax, so a reformat or
  a moved argument shows as what it is. The same file bar and hunk lines (no line in the hunk
  line), difftastic's two number columns, the same wrap. With the patch focused, lazygit shows
  git's raw diff.
- `plain`: delta alone, without `wt-hub-diff`: one number column, `path:line` on each hunk. Long
  lines do not wrap: they stop at the edge, and `H` / `L` scroll the patch to the side. With the
  patch focused, lazygit shows git's raw diff.

The hub's renderers do not read your `~/.gitconfig` `[delta]` settings, and use 24-bit color.
See `notes/lazygit-review.md` ("7. The diff") and the screen dumps in `notes/lazygit-diff/`.
Keys: [Review (lazygit)](keys.md#review-lazygit-wt_reviewlazygit).

## Files

`e` in tuicr (NORMAL or SELECT mode) opens files: yazi in the review's worktree, over review.
tuicr keeps running under it. `e` or `q` in yazi closes files, and review comes back. A new pick
moves files to the new worktree.

In files:

- `o` opens the hovered file in this pane (yazi's own open).
- `O` opens the hovered file or folder in your editor, in its project, in a new tab (`wt-edit`,
  see [Open your editor](working.md#open-your-editor)).
- `W` is yazi's "open with" menu (yazi's own `O`).

## Hide review

Ctrl g `v` hides review, and the agent viewer gets its width. Ctrl g `v` again shows review on
the right, at the width it had. The focus stays in the column that has it. Ctrl g `3` and Enter
on a worktree row also show a hidden review, and move the focus to it.

- tuicr runs on while review is hidden: your place and draft comments stay. New turns come in
  when review shows again.
- Files closes when review hides, and opens again when review shows.
- A fresh hub (`wt hub` after a quit) starts with review shown.

zellij cannot hide a tiled pane, so a hidden review is a floating pane of no size in the bottom
right corner, and the hub tab's floating panes are hidden. A new floating pane (Ctrl g Tab,
Ctrl g `r`) shows them again; the hub hides them again when that pane closes. Ctrl g `p` `w`
(zellij's floating panes key) shows them too: the list hides them again within 3 s.
