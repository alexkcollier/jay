# Orchestrators

[README](../README.md) · [Working in the hub](working.md) · [Review](review.md) ·
[Signs](signs.md) · [Commands](commands.md)

- [What an orchestrator is](#what-an-orchestrator-is)
- [Start one](#start-one)
- [The orchestrator prompt](#the-orchestrator-prompt)
- [How it makes workers](#how-it-makes-workers)
- [How it follows and steers workers](#how-it-follows-and-steers-workers)
- [Review and merge](#review-and-merge)
- [Skills and slash commands](#skills-and-slash-commands)
- [The signs](#the-signs)
- [Fresh context](#fresh-context)
- [An orchestrator in a worktree it entered](#an-orchestrator-in-a-worktree-it-entered)
- [The hub Claude and orchestrators](#the-hub-claude-and-orchestrators)
- [Probe sessions in tests](#probe-sessions-in-tests)
- [Example: from start to merge](#example-from-start-to-merge)

## What an orchestrator is

An orchestrator is a background agent in a repo's main checkout that has the orchestrator
prompt (`jay_orchestrator_prompt` in `lib/jay-lib.sh`). It is the orchestrator of that repo, as
the hub Claude is for all repos. It plans, reads, reviews and answers questions, and it gives
each change to a worker: a background agent in a new worktree (`jay new <branch> -t <task> --
<prompt>`). So no work piles up on main, the main checkout stays free of work, and agents do not
move between worktrees. The list marks an orchestrator with a cyan `◇` before its name.

The prompt only steers the agent. Claude's own rule still stops a background agent from editing
in the main checkout, and the agent can go into a worktree (`EnterWorktree`) when you tell it to
make a change itself (see
[An orchestrator in a worktree it entered](#an-orchestrator-in-a-worktree-it-entered)).

## Start one

Press `n` on the main checkout row of the repo (the worktree row with the home sign), or on an
agent row under it. `n` on the bold repo row does not start one: it asks you to pick a worktree
row.

1. When the repo has an orchestrator already, `n` does not start a second one. The list says so
   (`<repo> has an orchestrator: "<name>" (<id>). A repo has only one, so n does not start a
   second one.`), and the hub shows that orchestrator in the middle column.
2. When Claude does not trust the repo yet, the list asks first (`y: trust`) and writes the trust
   into `~/.claude.json`, as the trust prompt of `claude` would. `claude --bg` has no trust
   prompt of its own.
3. The list says "Starting an orchestrator in `<repo>` (main checkout)..." and runs, in the main
   checkout:

   ```sh
   claude --bg --name "<repo>/<branch>" --append-system-prompt "<the orchestrator prompt>"
   ```

   `<branch>` is the main checkout's branch, so the name is `shop/main`, say.
4. The hub shows the new agent in the middle column, idle, with the focus there. Type its first
   prompt.

A repo has one orchestrator. An agent that you start in the main checkout in another way (`c`,
`claude --bg`, an interactive `claude`) has no orchestrator prompt: it is a plain agent, and
`n` still starts an orchestrator.

## The orchestrator prompt

The list adds this text to the agent's system prompt (`--append-system-prompt`), with the
repo's name for `<repo>` and the path of its main checkout for `<main checkout>`:

```text
You are the orchestrator of the repo <repo>, in its main checkout <main checkout>, in jay, a worktree hub: a list
of worktrees and Claude agents. Each worker is a background Claude session in its own git
worktree (siblings named <repo>.<branch>). Plan, read, review and answer questions here; give each
change to a worker. Keep the main checkout free of work.

- New worker for a change: here, `jay new <branch> -t "<task>" -- <prompt>` (a new worktree
  and a background agent in it). Give it a prompt it can act on alone: the goal, the files, how
  to test. Start workers only when the user asks or agrees.
- Do not edit files in the main checkout, and do not use EnterWorktree: a change that you make
  yourself takes you into its worktree. When the user tells you to make a change yourself, do
  as they say.
- Skills and commands that change the branch or write (make or switch a branch, commit, rebase,
  push, stash, edit files) run in the worker of that branch, never here; the jay-guard hook
  denies such git commands here. A skill that only the user can start: tell the user which
  worker is ready for which command.
- Workers: `claude agents --json --all` (id, name, cwd, state, status); recent output:
  `claude logs <id>`; what a worker did per turn: `git log refs/wt-turns/<id>/base..refs/wt-turns/<id>/head`
  in its worktree. Send a prompt to a worker: the ListAgents and SendMessage tools.
- Worktrees with git state and task notes: `wt list` (worktrunk).
- Read the workers' worktrees in place; do not edit files in them. Never merge, and never remove
  worktrees or agents (`wt merge`, `wt remove`, `claude rm`), unless the user asks.
```

`wt list`, `wt merge` and `wt remove` are worktrunk's own commands; `jay new` makes the worktree
through worktrunk too. An orchestrator started before the rename keeps the old prompt (with
`wt new`): the shim runs `jay new` for it.

What each part tells the agent:

- **The first paragraph**: its role. It is the orchestrator of one repo, in the main checkout.
  Workers are background sessions in sibling worktrees named `<repo>.<branch>` (the hub's
  worktrunk setting). It plans, reads, reviews and answers; each change goes to a worker.
- **New worker**: the command that makes a worker, and what a good worker prompt has (the goal,
  the files, how to test). It starts workers only when you ask or agree.
- **No edits in the main checkout, no `EnterWorktree`**: it does not do the work itself. When you
  tell it to make a change itself, it does as you say (it then goes into a worktree).
- **Skills and commands**: one that changes the branch or writes runs in the worker of that
  branch. For a skill that only you can start, it tells you the worker and the command. See
  [Skills and slash commands](#skills-and-slash-commands).
- **Workers**: how it sees them (`claude agents`, `claude logs`, the turn chains of the hub) and
  how it talks to them (ListAgents, SendMessage).
- **Worktrees**: `wt list` gives the git state and the task notes.
- **Read only, no merge, no removal**: it reads the workers' worktrees in place and never edits
  them. It merges and removes only when you ask.

The prompt's first words, "You are the orchestrator", are the mark that tells an orchestrator
from another agent in the main checkout (`JAY_ORCH_MARK`). See [The signs](#the-signs).

## How it makes workers

The orchestrator runs `jay new <branch> -t "<task>" -- <prompt>` in the main checkout
(`bin/jay-new`):

1. `wt switch <branch> --no-cd --format=json` makes the worktree, with `--create` when the
   branch does not exist yet, locally or as `origin/<branch>` (`-b <base>`: the branch to start
   from). `pr:<N>` takes a pull request's branch. An existing worktree is used again. The
   worktree is a sibling of the main checkout, `<repo>.<branch>`.
2. The task note (`-t`, else the first line of the prompt, 60 characters) goes into worktrunk's
   state variable `task`. The list and `wt list` show it.
3. `claude --bg --name "<repo>/<branch>" "<prompt>"` starts the worker in the new worktree. `-a`
   in place of a prompt starts an idle worker.

The worker starts without the orchestrator's `CLAUDE*` and `ANTHROPIC*` variables. An inherited
`CLAUDE_CODE_CHILD_SESSION` would hide the worker from `claude agents` (so from the list) and
turn off its transcript. A worker has no orchestrator prompt: it is a plain background agent in
its worktree. The repo is trusted already, because the orchestrator runs in it.

You can make a worker yourself too: `N` on the repo row (an idle agent in a new worktree), or
`jay new` in a shell.

## How it follows and steers workers

The prompt gives the orchestrator these tools:

- `claude agents --json --all`: each agent's id, name, folder (`cwd`), state and status.
- `claude logs <id>`: a worker's recent output.
- `git log refs/wt-turns/<id>/base..refs/wt-turns/<id>/head` in the worker's worktree: what
  the worker did, one commit per turn (see [Review by turn](review.md#review-by-turn)). While a
  turn runs, `refs/wt-turns/<id>/live` holds the turn so far.
- `wt list`: the worktrees with their git state and task notes.
- ListAgents and SendMessage (Claude's own tools): send a prompt to a running worker, and get its
  answer. SendMessage can also ask for one notice when a session on this machine next goes idle
  (`notify_when_idle`).

You see the same in the hub: the worker's row and its sign, its turns in review, a notice when
its turn ends or it needs input. An orchestrator that only waits for its workers (state
`working`, status `idle`) does not count as working: the list shows it as unread or idle.

## Review and merge

The prompt says: never merge, and never remove worktrees or agents, unless you ask. The usual
flow:

1. The worker commits its change on its branch, and rebases the branch on main.
2. You review it in the hub: pick the worker, then review shows its turns; `t` in review shows
   the branch's own commits (commits mode). The orchestrator can review it too, and tell the
   worker what to change (SendMessage).
3. You tell the orchestrator to merge. It merges in the main checkout with
   `git merge --ff-only <branch>`. A fast-forward fails when main moved on: then the worker
   rebases again.
4. The worktree row now shows the dim check sign (safe to remove: integrated). `d` on the
   worktree row removes the worktree (`wt remove`), then its idle agents (`claude rm`), and
   closes its tasks tab. The branch is deleted only when it is merged. Or ask the orchestrator to
   run `wt remove` and `claude rm`.

## Skills and slash commands

The rule: a command that changes the branch or writes runs in a worktree. In its main checkout,
an orchestrator only reads, plans, reviews and steers workers. It merges there only with
`git merge --ff-only <branch>`, and only when you tell it to.

Why a rule for skills: Claude stops a background agent's file edits (Edit, Write) in the main
checkout, but it does not stop git through Bash. The project skills of a repo
(`.claude/skills`, tracked, so each worktree has them too) can run such git. Some examples:

- A pull request skill (`/open-pr`, say) makes a branch with `git checkout -b` when it is on the
  default branch, pushes it and runs `gh pr create`. Later it edits, commits and pushes the
  fixes for the review comments.
- A squash skill runs `git reset --soft`, a commit and a rebase.
- An audit skill runs `git checkout <PR branch>`.

In the main checkout, each of these moves main or changes its files. In a worker, they change
only the worker's branch.

| Kind of skill or command | Examples | Where it runs |
|---|---|---|
| Read and report | questions about the code, an audit or explain skill that only reads, `/context`, `/cost` | the orchestrator |
| Review with a target | `/code-review <branch>`, `/code-review <PR number>` | the orchestrator |
| Review that writes | `/code-review --fix` (it applies the findings to the files) | the worker of that branch |
| Branch, commit, history, push | a pull request skill, a squash or rebase skill, a skill that fixes review comments | the worker of that branch |
| Checkout of another branch | an audit skill that checks out a PR branch, `gh pr checkout` | a worker on that branch: `jay new pr:<N>` |
| Files and stash | a skill that edits, formats or generates files; `git stash`, `git clean` | the worker of that branch |

Many such skills have `disable-model-invocation: true` in their front matter: only you can
start them, when you type them. Claude does not start them on its own. The flow:

1. The orchestrator gets the worker ready: the change is committed and the tests pass.
2. It tells you which worker is ready for which command, for example: "shop/fix-login is
   ready for `/open-pr`".
3. You pick that worker in the list (the middle column shows it) and type the command there.
4. The skill runs in the worker's worktree, on its branch. The orchestrator follows the worker
   as usual (see [How it follows and steers workers](#how-it-follows-and-steers-workers)).

A skill that Claude can start itself goes to the worker in the same way: the orchestrator sends
the worker a prompt that asks for it (SendMessage).

### When such a skill runs in an orchestrator

When you type such a skill in the orchestrator, or the orchestrator starts one:

- Claude's own rule stops its file edits in the main checkout.
- The `jay-guard` hook stops its git and gh commands that change the main checkout (see below).
  Claude gets the reason: the command changes the main checkout, so give it to the worker of
  that branch, or run it in that branch's worktree. The orchestrator tells you, and the main
  checkout stays as it was.
- The skill stops at that step. Steps before it ran, but those only read.

Then give the skill to the worker of that branch, as above.

### The guard

`jay-guard` (`bin/jay-guard`) is a PreToolUse hook on Bash (`config/claude-settings-hooks.json`;
`./install.sh` adds it to `~/.claude/settings.json`). It runs before each Bash call of each
session:

- It acts only for an orchestrator: a background agent with the orchestrator prompt in its job's
  `respawnFlags` (`CLAUDE_JOB_DIR` gives the job), whose folder is the main checkout of its repo.
  For every other session it exits at once.
- It acts only on commands that run in the main checkout: in the Bash folder (`cwd`), or after a
  `cd` or `git -C` into it. A subfolder counts; a worktree in it (`.claude/worktrees/...`) does
  not. A command after `cd <worktree>` or with `git -C <worktree>` passes, also in a subshell.
- It reads compound commands: `&&`, `||`, `;`, `|`, new lines, subshells, `$(...)` and
  backticks, `bash -c '...'`, `eval`. Quotes, comments, redirections and heredoc bodies are not
  commands.

What it denies in the main checkout:

- `git checkout` and `git switch` (a branch, `-b`, `-c`, files), `git restore`, `git clean`,
  `git add`, `git rm`, `git mv`, `git apply`;
- `git branch <name>`, `-d`, `-D`, `-m`, `-c`, `-f`, `-u`; `git tag <name>`, `-a`, `-d`;
- `git commit`, `reset`, `rebase`, `cherry-pick`, `revert`, `am`, `pull`, `push`, `stash` (not
  `stash list` or `stash show`);
- `git merge` without `--ff-only` (also with `--squash` or `--no-ff`);
- `git worktree add`, `remove`, `move`, `prune` (worktrees come from `jay new`, a removal from
  `wt remove`);
- `git fetch` into a local branch (`origin a:b`), `git config` writes;
- `gh pr checkout`, `gh pr create`, `gh pr merge`, `gh repo sync`;
- a git command that it does not know (an alias, say), or whose folder or subcommand it cannot
  tell (`cd "$WT"`, `git -C "$(...)"`): when in doubt, it denies.

What it allows: `git status`, `log`, `diff`, `show`, `branch` (a list), `tag` (a list),
`rev-parse`, `merge-base`, `fetch`, `worktree list`, `for-each-ref`, `stash list`, `remote -v`,
`config --get` and other reads; `git merge --ff-only <branch>`; all `gh` commands except the
ones above; all other programs.

It checks only git and gh. Other programs that write files (`sed -i`, a formatter, an
install) are not checked: the orchestrator prompt covers them.

A denied call returns this JSON (exit 0), and Claude shows the reason as the tool's result:

```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
 "permissionDecisionReason": "jay-guard: `git checkout -b fix` is denied in the main checkout ..."}}
```

The deny holds also with `--permission-mode bypassPermissions`. An orchestrator started before
the guard has the old prompt, but the guard acts for it too: it looks only for the prompt's
first words.

## The signs

| Sign | Meaning |
|---|---|
| cyan `◇` before the name | the repo's orchestrator |
| yellow `◇` before the name | an extra agent with the orchestrator prompt in the same main checkout; remove it with `d` |
| no `◇` | any other agent, also one in the main checkout without the prompt |
| `→ <branch>` after the age | the orchestrator is in that worktree now (see below) |

How the list finds the orchestrator (`jay_jobs`, `jay_orch_ranks`, `jay_orchestrators`):

- Claude keeps the options that a background agent started with in its job's state:
  `respawnFlags` in `~/.claude/jobs/<id>/state.json`. An agent whose options have a string that
  starts with "You are the orchestrator" has the orchestrator prompt.
- The orchestrator of a repo is the oldest live agent with the prompt in its main checkout
  (`startedAt`). A stopped agent does not count. The others there are extra ones (yellow `◇`).
- Only a start outside the list makes an extra one, for example a copy from
  `claude --bg --resume` with new options. The hub Claude does not send work to it.
- An agent in the main checkout without the prompt (`c`, `claude --bg`, an interactive `claude`)
  is a plain agent: it gets no `◇`, the hub Claude does not send work to it, and `n` still starts
  an orchestrator.

Why this rule: the `◇` follows the prompt, so an agent with a `◇` always acts as an
orchestrator. The oldest one keeps the `◇`, so the sign does not move to a new agent. The list,
`n` and the hub Claude (`jay agents --orchestrators`) use the same rule, so they find the same
agent.

## Fresh context

`c` on an orchestrator row (cyan or yellow `◇`) or on the "◆ hub" row clears the agent's
context. After a confirm, the list types `/clear` into the agent through a hidden
`claude attach` (`jay clear`).

- **What stays**: the system prompt (so the orchestrator prompt), the name, the short id and the
  process. So its turn chain, `~/.local/state/jay/hub-claude` (for the hub Claude) and the middle
  column stay correct.
- **What changes**: the session id. The agent starts a new conversation. The old conversation
  stays in its transcript.
- **What it forgets**: all of the old conversation, also its workers. The workers keep running,
  and you see them in the list. Tell the new conversation about them when it must go on with
  them.
- **When**: only when the agent is idle or unread (`○` or `✓`). `/clear` typed into a question or
  a permission prompt would answer it. When the agent works, waits for you or failed, the list
  says so and does nothing. An agent that only waits for its workers (state `working`, status
  `idle`) is idle: `c` clears it.
- **Not** for an orchestrator in a worktree that it entered: that worktree would stay its folder
  after the `/clear`. Tell it to leave the worktree first (`ExitWorktree`), then press `c` again.
- **The shared input box**: all `claude attach` clients of an agent share one input box.
  `jay clear` deletes a draft in it first (Ctrl+U), so a draft that you typed in the middle
  column is lost.
- **The screen size**: the agent's screen takes the size of the client that joined last. So the
  hidden client takes the size of a client that is attached already (the middle column).
- For another agent, type `/clear` in the agent.

`jay clear <id>` exits 0 when the session id changed, 1 when it did not, 2 for a usage error
and 3 when the agent is missing or not idle.

## An orchestrator in a worktree it entered

When you tell the orchestrator to make a change itself, it goes into a worktree with
`EnterWorktree`. Claude keeps that in the job's `state.json` (`cwd` is where it came from,
`worktreePath` the worktree).

- It stays under its main checkout in the list, with its `◇` when it is the orchestrator, and
  `→ <branch>` after its age names the worktree it is in.
- Its pick shows that worktree in review.
- It does not belong to the worktree: `d` on the worktree stops while it is there (the list
  names it: "Came in from another folder"), and the prune does not remove it.
- `d` on the agent itself removes the worktree and then the agent, with the same checks as `d`
  on the worktree: `claude rm` keeps such an agent while its worktree is on disk.
- `c` refuses until it leaves the worktree (`ExitWorktree`).
- Its turn chain follows it. After `EnterWorktree` or `ExitWorktree`, the turn's changes so far
  get a commit `turn, in <old folder> · <prompt>`, then a commit `worktree · <new folder>` takes
  the files of the new worktree, so the next turn shows only its own changes.

`d` and the prune treat any agent that went into a worktree with `EnterWorktree` in this way,
also one that did not come from a main checkout.

## The hub Claude and orchestrators

The hub Claude ([The hub Claude](working.md#the-hub-claude)) works across repos. Its prompt
(`jay_hub_claude_prompt`) says:

- A repo can have one orchestrator, an agent in its main checkout with an orchestrator prompt
  (`◇` in the list).
- `jay agents --orchestrators` lists them, one line each: main checkout, id, name.
  `jay agents --orchestrators <main checkout>` gives only the one of that repo.
- Send work for such a repo to its orchestrator (SendMessage).
- An orchestrator only reads, plans and reviews: skills that change a branch run in its workers
  (see [Skills and slash commands](#skills-and-slash-commands)).
- For a repo without one, start workers yourself with `jay new`, or tell the user that `n` on the
  repo's main checkout row starts one.

So you can give a change to the hub Claude from anywhere, and it goes to the right repo's
orchestrator.

## Probe sessions in tests

A test that starts Claude sessions (for example a check of the orchestrator prompt) must:

- start them with every `CLAUDE*` and `ANTHROPIC*` variable unset, in a pty: an inherited
  `CLAUDE_CODE_CHILD_SESSION` turns off the transcript and hides the session from
  `claude agents`, so the test sees something else than the user does;
- remove them at the end with `claude rm <id>`: without the `CLAUDE*` variables, such a session
  shows in your hub list (and an orchestrator probe would take the `◇` of a repo, or get a yellow
  one).

Only workers that `jay new` made for real work stay. See [CLAUDE.md](../CLAUDE.md).

## Example: from start to merge

A made-up repo `acme/shop` with a bug in the login redirect:

1. In the list, press `n` on the `main` row of `shop` (the home sign). The list starts the
   orchestrator. The middle column shows `shop/main`; its row gets a cyan `◇`.
2. Type: "Login loses the return URL after the redirect. Find the cause and give the fix to a
   worker." The orchestrator reads the code and tells you its plan.
3. You agree. It runs `jay new fix-login -t "keep the return URL on login" -- <prompt>`. A new
   worktree row `fix-login` shows under `shop`, with the task note, and the worker
   `shop/fix-login` (`●`) under it.
4. Pick the worker row: the middle column shows the worker, and review shows its turns, the
   running turn first. The orchestrator row shows `○`: it waits.
5. The worker's turn ends: its row shows `✓`, and a notice "✓ Turn finished · acme › shop"
   comes. The worker committed the fix: the row shows `+1`.
6. Ask the orchestrator to review the branch. Press `t` in review to see the branch's commits.
7. Tell the orchestrator: "Have the worker rebase on main, then merge it." It sends the worker
   the rebase (SendMessage), then runs `git merge --ff-only fix-login` in the main checkout. The
   `fix-login` row shows the dim check sign.
8. Press `d` on the `fix-login` row and `y`. The worktree, the worker and the merged branch go.
9. For the next topic, press `c` on the orchestrator row: it starts a fresh conversation, with
   the same prompt.
