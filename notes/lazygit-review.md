# lazygit as the review pane: a study

Date: 2026-10-21. Branch: `lazygit-review`. Versions: lazygit 0.66.2, tuicr 0.27.0,
zellij 0.45.1, git 2.54.0.

Status: lazygit is now an option (`WT_REVIEW=lazygit`), with the install steps, the prune and
the README of the "Cost" list below. tuicr stays the default. The study text below is as
written before that step. The patch in the review column got its own renderers later: see
[7. The diff](#7-the-diff).

This study answers six questions: can lazygit be the review pane of the hub, in place of tuicr
or next to it? The evidence is the lazygit 0.66.2 source (tag `v0.66.2`), commands, and tests
in throwaway zellij sessions with a fake HOME. The test repo is `shop`, with a real turn chain
from `bin/claude-turn-snapshot`.

## Summary

| Question | Answer |
|---|---|
| 1. Hidden refs | Not directly. A **view repo** works: one commit for each turn, with its diff. |
| 2. New turns | Yes. lazygit 0.66 refreshes by itself when a branch moves. The prototype selects the new turn. |
| 3. Own config | Yes. `CONFIG_DIR` + `LG_CONFIG_FILE` load your config, then the hub's. `t` and `e` are lazygit custom commands; `wt-hub-keys` is not necessary. |
| 4. Narrow column | Good at 40 to 80 columns with portrait settings. Better than tuicr at 40 columns. |
| 5. Features | tuicr has review comments, reviewed marks and export to the agent. lazygit has none of these. lazygit has git operations, range diffs and a live list. |
| 6. Recommendation | **Offer lazygit as an option** (`WT_REVIEW=lazygit`). Keep tuicr as the default. |

A prototype is on this branch (commit `0a61e22`). It is not installed: the live install links to
the main checkout.

- `bin/wt-hub-lazygit`: runs lazygit for the review pane (turns or commits).
- `config/lazygit/hub.yml`: the hub's lazygit settings.
- `bin/wt-hub-pane`: with `WT_REVIEW=lazygit`, the review role runs `wt-hub-lazygit`.
- `lib/wt-lib.sh`: reads `WT_REVIEW` from `~/.config/wt-hub/config`.

## 1. Can lazygit show a turn chain from hidden refs?

### Directly: no

- The commits panel shows `git log <ref>` for the checked-out ref only. `getLogCmd` uses
  `opts.RefName` (`pkg/commands/git_commands/commit_loader.go:597`). The refresh gives it HEAD
  or the checked-out branch (`refreshCommitsWithLimit`,
  `pkg/gui/controllers/helpers/refresh_helper.go:842`).
- The branches panel lists `refs/heads` only (`branch_loader.go:385`). Tags and remotes use
  their own namespaces. lazygit does not show `refs/wt-turns/*` anywhere.
- `lazygit --help` has no argument for a ref or a range. `-f` is a path filter
  (`git log -- <path>`), not a ref filter.

### Options

| Option | Result |
|---|---|
| A temporary branch in your repo (`refs/heads/...`) | Works, but `git branch`, `wt list`, the hub list and `git push --all` see it. The turns are hidden on purpose. Rejected. |
| A detached worktree (`git worktree add --detach`) | `git worktree list` and the hub list show it, and it checks out all files. Rejected. |
| A custom command with `git log` in a popup | Text only: you cannot select a turn or see its diff. Rejected. |
| The path filter (`-f`) | Filters by path, not by ref. Does not apply. |
| **A view repo** (prototype) | Works. See below. |

### The view repo

`wt-hub-lazygit turns <id>` makes `~/.local/state/wt-hub/lazygit/views/<id>`, a git repo of its
own:

- `objects/info/alternates` points to the objects of your repo. The view reads your commits and
  writes nothing to your repo.
- Branch `turns` is the chain head (checked out). Branch `turns-base` is the base.
- The view's `.git/lazygit.yml` sets `git.mainBranches: [turns-base]`. lazygit then shows the
  turns as not merged (yellow `*`) and the base and the history under it as merged (green `*`).
- The index has the head's tree with the skip-worktree bit on each file. Thus the empty work tree
  has no changes: `git status` in the view shows 0 lines.
- A commit, branch, reset or rebase in lazygit changes only the view. After the test, your repo
  had the same refs as before (`refs/heads/feature`, `refs/heads/main`, the two `refs/wt-turns`
  refs) and the same `git status`.
- Size: 112K for the test view. A sync on a repo with 50,000 files took 0.09 s
  (`read-tree` + `update-index --skip-worktree`), and `git status` in the view took 0.05 s.

Capture (review pane at 60 x 30, turns mode, newest turn selected):

```
╭─Commits - Files - Local branches─────────────────────────╮
│* 2:49PM (HEAD -> turns) turn · add a license             ▐
│* 2:49PM turn · add a readme                              ▐
│* 2:46PM turn · remove feat                               ▐
│* 2:46PM turn · change app line 2                         ▐
│* 2:46PM turn · add a greeting                            ▐
│* 2:46PM (turns-base) feature: add feat.txt               ▐
│* 2:46PM main commit 3                                    ▐
│* 2:46PM main commit 2                                    │
╰───────────────────────────────────────────────────1 of 9─╯
╭─Patch────────────────────────────────────────────────────╮
│commit 974c66aa29e1bccade4cd22bf3d737c492282afd (HEAD ->  ▐
│turns)                                                    ▐
│Author: Tester <a@b.c>                                    ▐
│Date:   Wed Oct 21 14:49:54 2026 -0400                    ▐
│                                                          ▐
│    turn · add a license                                  ▐
│                                                          ▐
│    result: license added                                 ▐
│---                                                       │
│ LICENSE | 1 +                                            │
│ 1 file changed, 1 insertion(+)                           │
│                                                          │
│added: LICENSE                                            │
```

The patch shows the turn's prompt and the agent's result line (the commit body).

All turns as one diff (tuicr's second `(`): select a range with `v` and `j`. The test showed
"Showing diff for range 18b9455-974c66a" with the 6 files of the 5 turns.

The base row and the history under it stay in the list. A `shallow` file in the view (with the
base commit) stops the log at the base: tested with `git log` on a copy of the view. But then the
base row shows its full tree as new files. The prototype does not use it.

**Commits mode** needs no trick: `lazygit log` in the worktree shows the branch's commits on top,
and main's commits as merged.

## 2. Can lazygit follow new turns and open on the newest?

### Refresh

lazygit 0.66 has `git.autoDetectExternalChanges` (default `true`) and
`refresher.externalChangeCheckInterval` (default 2 s). Each 2 s it reads `refs/heads` and HEAD.
When they change, it refreshes all views (`pkg/gui/background.go:170` to `:217`,
`RefsSnapshot` in `pkg/commands/git_commands/status.go:90`).

- `refs/wt-turns/*` is not in that snapshot. Thus lazygit on your repo does not see a new turn.
- In the view repo, the branch `turns` moves. `wt-hub-lazygit` copies the chain head into the
  view every 2 s, and lazygit refreshes by itself.
- lazygit has no socket, signal or remote control for a refresh. The only input is the keyboard
  (`R` refreshes) and zellij `write-chars`.
- tuicr restarts on each new turn, and you lose your place. lazygit does not restart: your place,
  open views and selection stay.

Test: a new turn came in while lazygit ran. The list showed it 1 s later (the time depends on the
two 2 s loops: 4 s at most).

### The selection after a refresh

A background refresh keeps the selected commit by its hash (`KeepCommitSelectionByHash`,
`pkg/gui/types/refresh.go:35`). There is no setting for this.

- Test: with turn 2 of 7 selected, a new turn came in. The selection stayed on the same turn,
  now "3 of 8". This is correct when you read an older turn.
- Test: with the newest turn selected ("1 of 8"), the selection stayed on that turn, now
  "2 of 9". The new turn was not selected.

The prototype adds this: before a sync, it reads the commits frame ("─1 of 10─╯") with
`zellij action dump-screen`. When the newest turn was selected, it waits until lazygit shows the
new count, then types `<` (go to top) into the pane. Test: "1 of 10" became "1 of 11" with the
new turn selected. When the selection is on an older turn, it types nothing.

Limit: the same as tuicr's `(` helper. It reads the screen. A popup over the frame stops it; it
then types nothing.

### Open on the newest turn

`lazygit log` opens with the commits panel focused, and the first row (the newest turn) is
selected. The `(` helper of tuicr (`select_last_turn` in `wt-hub-pane`) is not necessary.

## 3. Can the hub use its own lazygit config?

### Config files

- `LG_CONFIG_FILE` is a list of files with `,` between them. Each file overrides the file before
  it (`pkg/config/app_config.go:91`). `-ucf` / `--use-config-file` is the same.
- `CONFIG_DIR` sets the folder for `state.yml` (`app_config.go:796`). lazygit keeps the recent
  repos there. Without it, your recent repos get the view repos.
- A repo can have its own `.git/lazygit.yml`. The view repo uses it for `mainBranches`.

`wt-hub-lazygit` sets:

```
CONFIG_DIR=~/.local/state/wt-hub/lazygit/state
LG_CONFIG_FILE=<your config.yml>,<config/lazygit/hub.yml>
```

`<your config.yml>` comes from `lazygit --print-config-dir` (on macOS:
`~/Library/Application Support/lazygit`). Test: a copy of your config (delta as diff renderer)
in the fake HOME. The hub's lazygit showed delta's output ("added: LICENSE" and its frame). Your
lazygit outside the hub does not read the hub's file.

### Settings in `config/lazygit/hub.yml`

| Setting | Why |
|---|---|
| `gui.sidePanels: [[commits, files, branches]]` | One tab group: the column is narrow. Commits is first, so `lazygit log` opens on it. |
| `gui.portraitMode: always`, `screenMode: half`, `enlargedSideViewLocation: top` | List on top, patch under it. |
| `gui.commitAuthorShortLength: 0`, `commitAuthorLongLength: 0`, `commitHashLength: 0` | More space for the subject. The patch shows the author and the hash. |
| `git.log.showGraph: never` | A turn chain has no merges. The graph takes 2 columns. |
| `gui.showRandomTip`, `showCommandLog`, `showPanelJumps`, `showBottomLine: false` | Less noise. The pane title shows the hub keys. |
| `disableStartupPopups: true`, `update.method: never`, `git.autoFetch: false` | No popups and no network in the review pane. |
| `promptToReturnFromSubprocess: false` | No "press enter" after a command. |

### Keys

| Key | lazygit default | Hub |
|---|---|---|
| `t` | revert commit (commits panel) | custom command: `wt-hub-lazygit --toggle` (writes the mode, stops lazygit; `wt-hub-pane` starts the other mode) |
| `e` | edit file | custom command: `wt-sidebar --files` (yazi over review). lazygit's "open file" stays on `o`. |
| `q` | quit | not changed: `wt-hub-pane` starts lazygit again, which means "back" (to the newest turn). |
| `v` | range select | not changed. Hide review is Ctrl g `v`, a zellij key; lazygit does not get it. |

- Custom keys come before lazygit's own keys: "prepending because we want to give our custom
  keybindings precedence" (`pkg/gui/keybindings.go:350`). The config also sets
  `commits.revertCommit` and `universal.edit` to `<disabled>`.
- lazygit does not run custom keys while you type in a prompt. Test: `/` (search), then `te`.
  The prompt showed "Search: te", the mode file stayed `turns`, and no files pane opened.
- Thus `wt-hub-keys` is not necessary for lazygit. It reads tuicr's status line to know when keys
  are commands; lazygit knows this itself. `wt-hub-keys` stays for tuicr.

Tests in the throwaway session, all through `wt-hub-pane review`:

- `q`: lazygit quit and started again on the newest turn.
- `t`: the mode file became `commits`, the title became `commits · shop   e files · t turns`,
  and lazygit showed the branch's commits. `t` again: back to turns.
- `e`: yazi opened over review (`files · shop ...`). `q` in yazi: review came back, and lazygit
  had its place.
- Ctrl g `v` (as `wt-sidebar --review toggle`): review became a floating pane of size 0, and
  lazygit ran on. Show: review came back at 60 columns. lazygit drew again at 60 columns.
  zellij kept 13 old cells to the right of each row (from a draw at 73 columns during the show).
  They are outside the screen (review is the last column) and do not show. tuicr clears the
  screen on a resize and has no such cells.
- A retarget (a new pick, `wtl_hub_point`): lazygit and its follow loop stopped. A worktree with
  no chain opened lazygit on the worktree (tuicr opens its picker there).

## 4. A narrow right column

Captures from `zellij action dump-screen` in throwaway sessions.

40 x 24, turns:

```
╭─Commits - Files - Local branches─────╮
│* 2:49PM (HEAD -> turns) turn · add a ▐
│* 2:49PM turn · add a readme          ▐
│* 2:46PM turn · remove feat           ▐
│* 2:46PM turn · change app line 2     ▐
│* 2:46PM turn · add a greeting        │
│* 2:46PM (turns-base) feature: add fea│
╰───────────────────────────────1 of 9─╯
╭─Patch────────────────────────────────╮
│commit                                ▐
│974c66aa29e1bccade4cd22bf3d737c492282a▐
│fd (HEAD -> turns)                    ▐
│Author: Tester <a@b.c>                ▐
│Date:   Wed Oct 21 14:49:54 2026 -0400▐
│                                      │
│    turn · add a license              │
│                                      │
│    result: license added             │
│---                                   │
│ LICENSE | 1 +                        │
│ 1 file changed, 1 insertion(+)       │
│                                      │
╰──────────────────────────────────────╯
```

tuicr at 40 x 24 on the same chain. The subjects do not show:

```
 tuicr  git:feature · commit 1/5 · shop@
┌ Commits ─────────────────────────────┐
│▸ ▌ ▣   974c66a   Tester       · 7m   │
│    ▢   7dad53d   Tester       · 7m   │
│    ▢   ef8c18d   Tester       · 10m  │
│    ▢   9b5f087   Tester       · 10m  │
│    ▢   18b9455   Tester       · 10m  │
└──────────────────────────────────────┘
┌ Commit Message (974… ───────── +0 -0 ┐
│▶ ═══ Commit Message (974c66a) ═══════│
```

40 x 24, Enter on a turn (its files), then Enter on a file:

```
╭─Diff files (ef8c18d turn · remove fe─╮   ╭─Patch────────────────────────────────╮
│▼ /                                   │   │diff --git a/feat.txt b/feat.txt      ▐
│  D feat.txt                          │   │deleted file mode 100644              ▐
│  ▼ src                               │   │index c774709..0000000                ▐
│    A main.rs                         │   │--- a/feat.txt                        ▐
│                                      │   │+++ /dev/null                         ▐
╰───────────────────────────────1 of 4─╯   │@@ -1 +0,0 @@                         ▐
╭─Patch────────────────────────────────╮   │-feat                                 ▐
│                                      ▐
│removed: feat.txt                     ▐
```

(Two captures side by side.) The file view is lazygit's line view for custom patches. It does
not use your diff renderer.

60 x 20 shows 5 list rows and 11 patch lines. 80 x 40 shows 11 list rows and 24 patch lines.
Both are easy to read.

Notes:

- The patch wraps long lines (`gui.wrapLinesInDiffView: true`). The `commit <hash>` header takes
  2 or 3 rows at 40 columns.
- `+` and `_` change the screen mode (normal, half, full). Full gives the patch the full pane.
- I did not test fewer than 20 rows.

## 5. What each tool does that the other cannot

tuicr's key help (`?`) lists these. lazygit has none of them:

- Line, file, range (visual mode) and review comments; edit and delete a comment.
- Export: `y` copies the review (comments with file and line) to the clipboard, to paste into
  the agent. This is the review-to-agent loop.
- Marks: a file or a hunk "reviewed" (`r`, `R`); `:set noreviewed` hides reviewed files; `✓`
  marks commits that your last review covered.
- Review sessions that stay (`tuicr review`) and PR/MR review with submit (`tuicr pr`).
- Include and exclude filters for files (`i`, `e`), a single-file view, side-by-side diffs,
  context expansion (Enter).

lazygit has these. tuicr has none of them:

- Git operations: stage, commit, amend, reword, interactive rebase, cherry-pick, reset, stash,
  branches, push, pull, worktrees. In commits mode they act on the worktree. In turns mode they
  act on the view only.
- A custom patch from a commit: move part of a commit, or remove it. (In turns mode this acts on
  the view, not on the worktree.)
- A live list that refreshes without a restart, and keeps your place.
- Range select (`v`) for one diff over many commits, and a diffing mode (`W`) between any two refs.
- Your own diff renderer (delta), search and filter in each list, custom commands, mouse.
- The subjects show at 40 columns.

## 6. Recommendation

**Offer lazygit as an option. Keep tuicr as the default.**

- The hub's review is a loop: you read the agent's turn, write comments, and give them to the
  agent. tuicr does this (`c`, `y`). lazygit cannot write a comment. Thus lazygit cannot replace
  tuicr.
- lazygit is better for these: a quick read of turns in a narrow column, a live list without
  restarts, and commits mode with full git (for example a fixup or a rebase before a merge).
- A setting `WT_REVIEW=lazygit` in `~/.config/wt-hub/config` costs little: the prototype has it.

Do not run both in the review column at the same time: the column is narrow. A key to switch
between them (for example `g`) is possible later: the same exit-and-restart as `t`.

### Cost to finish the option

Files to change:

| File | Change |
|---|---|
| `bin/wt-hub-lazygit` | Done (prototype). Add `--prune <id>` to remove a view. |
| `config/lazygit/hub.yml` | Done (prototype). |
| `bin/wt-hub-pane` | Done (prototype). Update the text "tuicr opens here" for lazygit. |
| `lib/wt-lib.sh` | Done: `WT_REVIEW` in the settings. Optional: titles for lazygit (`wtl_hub_pane_title`). |
| `bin/claude-turn-snapshot` | `--prune`: also remove `~/.local/state/wt-hub/lazygit/views/<id>`. |
| `install.sh` | When `WT_REVIEW=lazygit`: check `lazygit` 0.66 or later (`brew install lazygit`); link or copy `config/lazygit/hub.yml` to `~/.local/share/wt-hub/lazygit/hub.yml`; `--uninstall` removes it and `~/.local/state/wt-hub/lazygit`. |
| `README.md` | Settings table (`WT_REVIEW`), "Review by turn", "Review keys" (a lazygit table), "Requirements", "State and logs" (the views). |
| `TODO.md` | Optional. |

New install steps: `brew install lazygit` (only for the option) and the hub config file. No new
hook. The user's lazygit config does not change.

Then: `./install.sh --link` in the main checkout for the new script, a test with a fake HOME
(`HOME=<tmp> ./install.sh`), and a test of `WT_REVIEW=lazygit` in a throwaway session.

### Risks

- Version: `git.autoDetectExternalChanges` is in lazygit 0.66 (tested: 0.66.2). An older lazygit
  does not refresh by itself. `install.sh` must check the version.
- The `<` helper reads the screen, the same as tuicr's helpers. A change in lazygit's frame text
  ("1 of 9") stops it. Then the new turn shows, but is not selected.
- Commits mode runs lazygit on the worktree. An agent can work there at the same time. Two git
  writers can collide on `index.lock`. tuicr only reads.
- Views stay on disk until a prune removes them (about 100K each).

## 7. The diff

Date: 2026-10-21. Branch: `lazygit-diff`. Versions: lazygit 0.66.2, delta 0.19.2, difftastic
0.71.0 (installed for this work: `brew install difftastic`, 119 MB), zellij 0.45.1.

Before: the hub's lazygit used your renderer from `config.yml`
(`delta --dark --paging=never --24-bit-color=never`, with `line-numbers` and `navigate` from
`~/.gitconfig`). Three complaints in a column of 60 to 80 columns:

1. The line numbers take 10 columns (`  7 ⋮ 10 │`).
2. The patch has no position: you cannot see the file, the part of it, or your progress.
3. Long lines wrap badly.

### Facts

- **Width.** A renderer command is a Go template with `{{width}}` (the patch view's inner
  width: 58 in a pane of 60), `{{columnWidth}}` (`width/2 - 6`), `{{colorScheme}}` (`dark` or
  `light`); `{{if gt .width 100}}` works too (`pkg/config/diff_renderer_config_manager.go:108`).
  lazygit runs it in a pty of the view's size and sets `COLUMNS` and `TERM=dumb`
  (`pkg/gui/pty.go:14`, `main_view_render.go:254`). Thus delta knows the width: its rules fill
  the view.
- **Wrap (complaint 3).** delta wraps only in side-by-side mode (`wrap-max-lines`, `↵` marks).
  In unified mode it writes each line in full, and lazygit wraps it
  (`gui.wrapLinesInDiffView`): the rest of the line starts at column 0, under the numbers. With
  `wrapLinesInDiffView: false` lazygit cuts the line at the edge, and `H` / `L` scroll the patch
  to the side. Nothing marks a cut line.
- **Position (complaint 2).** The patch view has no footer and no "x of y"; only the lists have
  one, and its scrollbar. Enter on a turn shows its files, one file at a time in the patch; the
  frame shows the row ("9 of 13", folders count too). A focused patch (`0`, a click) has `n` /
  `N` (next / previous file), `l` / `h` (next / previous hunk) and a selection. Ctrl g (jump to
  file) is zellij's key in the hub.
- **Focused patch.** lazygit 0.66 acts on a focused patch only when it can read it: git's raw
  diff, or a renderer that writes OSC 1717 records (`ESC ] 1717 ; 1 ; type ; new ; old ; path
  BEL` before each row, a handshake first; `diff_line_parser.go:421`). For any other renderer it
  shows git's raw diff while the patch has the focus (`diff_line_raw_fallback.go`): no syntax
  colours. This is the raw diff that you saw after a click on the patch.
- **Colour.** lazygit draws 24-bit colour (`gocui.OutputTrue`), and zellij passes it: the
  `--ansi` dumps have `48;2;0;40;0` cells. `--24-bit-color=never` is not necessary in the hub.
- **delta.** `--line-numbers-left-format` / `--line-numbers-right-format` (`{nm}`, `{np}`) give
  one column. `--hunk-header-style='file line-number syntax'` puts `path:line:` on each hunk. The
  labels (`--file-modified-label`, `--hunk-label`) are fixed text. No option counts files or
  hunks. `--navigate` does not work in lazygit (lazygit's docs). Tabs are 8 columns.
- **difftastic.** `difft --display=inline` shows one number on each row: the old column for an
  unchanged or removed row, the new column for an added row (two columns that alternate, 6
  columns for a file under 100 lines). Each hunk has `path --- 2/3 --- Python`. Inline mode does
  not wrap; side-by-side wraps, but has 29 columns a side at 60. A removed line whose tokens all
  stay in the new code does not show (a diff of the syntax). Run as git's external diff
  (`type: extDiff`), it gets `GIT_DIFF_PATH_COUNTER` / `GIT_DIFF_PATH_TOTAL` from git.
- lazygit's built-in diff has no syntax colours: not an option.

### The options

`bin/wt-hub-diff` is a new filter (python, like `wt-hub-keys`). With delta it is a stdin filter:
it reads git's diff, counts the files and hunks, runs delta with fixed options (marks on the
file and hunk headers, a gutter of `<old>|<new>|`, `--no-gitconfig`), and draws the result
again for the width. With difftastic it is git's external diff, one file a call.
`config/lazygit/hub.yml` lists three renderers; `WT_REVIEW_DIFF` loads `diff-difft.yml` or
`diff-plain.yml` over it, which puts that one first. `|` in lazygit goes to the next one.

| | 1. numbers | 2. position | 3. wrap | focused patch |
|---|---|---|---|---|
| own (before) | 10 columns | the file box; `• 24: def …` on a hunk | under the numbers | git's raw diff |
| **`delta`** (default) | 3 columns: `10│` (new line; old line in red on a removed row) | bar `5/8  M  src/orders.py  +12 -3`; `── src/orders.py:24 2/3 def handler_3(…`; `n`/`N`/`l`/`h` | under the code, at a space or comma | stays; `n`/`N`/`l`/`h` |
| `difft` | 6 columns (difftastic's two) | the same bar (language for counts); `── src/orders.py 2/3` | under the code | git's raw diff |
| `plain` | 5 columns: `  10│` (no number on a removed row) | `src/orders.py:24: def …` on a hunk | no wrap: cut, `H` / `L` | git's raw diff |

In the files panel (one file in the patch) the bar has no `1/1`: the frame shows the place.

Tests (navigation, from the `--ansi` dumps, `delta` at 60 columns): after `0` and `l` the
selection is on the first change (`Makefile` line 3); after `l l` on the deleted
`docs/README.md`; after `n` on the bar `4/8 scripts/deploy.sh`; after `n` on `5/8 src/orders.py`.
Edge cases with both modes: a binary file (`bin`), an empty new file, a mode change (`+x`), a
path with a space, a rename (`R  web/price.js -> web/format.js`), a 700-character line, tabs,
wide characters (`価格`, an emoji). Time: 12,000 lines of `git log -p` in 0.5 s (delta alone:
0.24 s).

The screen dumps are in `notes/lazygit-diff/60.txt`, `80.txt` and `120.txt`: the four
renderers at each width, in three views (the turn with the list, `src/orders.py` alone, the
focused patch after `n` four times). Plain text: the colours and the selection do not show.

### Recommendation

**`delta` (the default).** It is the only option that solves all three complaints, and the
only one that keeps its colours when the patch has the focus, where `n` / `N` and `l` / `h` jump
by file and hunk. `difft` is better to read a reformat or a moved argument, but has wider
numbers and the raw diff on focus: keep it a `|` away. `plain` has no script: use it if
`wt-hub-diff` breaks on a diff.

Limits of `wt-hub-diff`:

- It reads delta's output: the marks and the gutter come from options that it sets itself. A
  delta release that changes that output stops the bars and the gutter (the rows then show as
  delta wrote them). Tested with delta 0.19.2.
- It reads the whole diff before it writes (for the counts). A very large diff shows later.
- Your `~/.gitconfig` `[delta]` settings do not apply in the hub (a `side-by-side` there would
  break the parse). Extra delta options go after `{{colorScheme}}` in `hub.yml`.
- difftastic's hunk line has no line number: its header has none.

How to repeat: as in "How to repeat the tests" above, with the chain of `shop` (3 turns; turn 2
has 8 files and 13 hunks with long lines), `WT_REVIEW_DIFF=<option>` in the fake config, a pane
of 60, 80 or 120 columns (`borderless=true`, `--pane-frames false`), 40 rows, and the keys `j`,
Enter, `j` x 8, Esc, `0`, `+`, `n` x 4.

## Incident during the study

A test of `e` opened a files pane in the live `hub` session, over its review pane. The cause:
`wt-sidebar --files` (from lazygit's `e`) uses `WT_HUB_SESSION`, and `lib/wt-lib.sh` sets it
to `hub` when it is empty. The test pane did not export it. The pane was later gone and the
review pane came back (I did not close it myself: the permission check stopped that).

The fixes on this branch:

- `wt-hub-lazygit` exports `WT_HUB_SESSION` (from `ZELLIJ_SESSION_NAME`). Its custom commands
  thus act on the session that lazygit runs in.
- `CLAUDE.md` has a new rule: a test layout that runs hub scripts must export
  `WT_HUB_SESSION=<test session>`, and the test must unset the `ZELLIJ*` variables of the
  agent's own pane.

The tuicr path has the same gap: `wt-hub-keys` calls `wt-sidebar --files` with the variable
from the environment. In the live hub, the value `hub` is correct.

## How to repeat the tests

1. Make a fake HOME with `.local/bin` and `.local/lib` links to this branch, and a
   `.config/zellij/config.kdl` with `show_startup_tips false` and `show_release_notes false`.
2. Put `WT_REVIEW=lazygit` in the fake `~/.config/wt-hub/config`. Link `yazi` into the fake
   `.local/bin` (mise shims do not work with a fake HOME).
3. Make a repo and a chain: send `UserPromptSubmit` and `Stop` JSON to
   `bin/claude-turn-snapshot` with `HOME=<fake>`.
4. Write `<worktree>\t<chain id>` to `<fake>/.local/state/wt-hub-review.target`.
5. Start a session with a layout whose right pane runs
   `env HOME=<fake> WT_HUB_SESSION=<name> PATH=<fake>/.local/bin:... wt-hub-pane review`.
   Unset all `CLAUDE*`, `ANTHROPIC*` and `ZELLIJ*` variables first.
6. Attach a pty client of a fixed size (`python3 -I`, `pty.fork`, `TIOCSWINSZ`). Send keys
   through it, and read the pane with `zellij -s <name> action dump-screen -p terminal_2`.
7. Stop the session with `pkill -9 -f 'zellij --server .*/<name>$'`.
