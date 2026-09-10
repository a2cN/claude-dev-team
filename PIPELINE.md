# Claude Dev Team — Pipeline Spec

This document is the orchestration contract for the seven agents in
`agents/`. Read this before running a task through the pipeline for the
first time — it's the piece that ties the individual role definitions
together into a working process.

## The one thing to understand before anything else

**A Claude Code subagent cannot invoke another subagent in a reliable,
automatic chain the way your main conversation can.** Each agent in
`agents/` is a separate, isolated context. When one finishes, it returns
control to whoever invoked it — normally you, the human operator, typing
in your main Claude Code session. Nothing in this harness automatically
moves the task from "architecture done" to "now the designer runs."

This is why every artifact in this pipeline ends with a short "Next:"
instruction telling you, in plain language, which agent to invoke next.
The Project Manager agent (`agents/project-manager.md`) is the closest
thing to an orchestrator here, but even it does not spawn other agents by
default — it reads the workspace and tells *you* what to run next. You are
the actual orchestrator. This document's "Running a task, turn by turn"
section below is written with that in mind: it tells you exactly what to
type at each step.

(There is a more advanced, optional pattern — running an entire session
*as* the Project Manager via `claude --agent project-manager`, which does
grant access to the `Agent` tool and the ability to spawn subagents
directly. This harness doesn't build on that pattern by default, because
relying on automatic subagent-spawns-subagent chains across a multi-hour,
resumable, human-gated pipeline is more fragile and less auditable than
having a human explicitly trigger each stage. If you want to experiment
with it once you're comfortable with the manual flow, see "Advanced:
letting the Project Manager drive" at the end of this document.)

## The artifact pipeline

```
00_request.md          <- written by the human, not an agent
   |
   v
10_product_brief.md    <- Product Manager
   |
   v
20_project_plan.md      <- Project Manager            } HUMAN GATE: plan approval
   |                       (also creates STATUS.md)
   v
30_architecture.md      <- Solution Architect
   |
   v (only if the plan marks Design as required)
40_design_brief.md   \  <- Designer  (both written in one invocation;
45_design_approval.md/                 skipped otherwise)
   |
   v (only when no approved canon exists yet)
44_mock_build.md        <- Developer, mock only — does NOT go to QA
   |
   v                                                 } HUMAN GATE: design approval
   |   45_design_approval.md is signed here, and promoted to
   |   docs/design/<slug>/README.md immediately — before implementation
   v
50_implementation.md    <- Developer         <---+
   |                                              |
   v                                              | REJECT (rework, capped at 2 cycles)
60_qa_report.md          <- Quality Assurance -----+
   |
   v PASS
90_completion.md         <- Project Manager            } HUMAN GATE: completion approval
   |
   v (only after that gate is signed)
promote, then archive   <- Developer
   |
   v
git commit / push / PR  <- the human, never an agent

70_process_review.md    <- Process Advisor (optional, any time, doesn't gate anything)
```

The numbers read in **completion order**, which is why `44` comes before
`45` in time but after it in the diagram: the Designer *drafts* `45` in the
same invocation as `40`, the Developer *answers* it by building the mock in
`44`, and the human *completes* `45` by choosing and signing.

Every artifact lives in one task workspace:

```
.claude-dev-team/workspace/<task-slug>/
  00_request.md
  10_product_brief.md
  20_project_plan.md
  STATUS.md
  30_architecture.md
  40_design_brief.md        (only if Design is required)
  44_mock_build.md          (only if a mock had to be built and looked at)
  45_design_approval.md     (only if Design approval is required)
  50_implementation.md      (revised in place across rework cycles)
  60_qa_report.md           (revised in place across rework cycles)
  70_process_review.md      (optional, any point)
  90_completion.md
```

One document the pipeline uses is deliberately **not** in there:
`docs/OPEN-DECISIONS.md`, the project's open-decisions ledger. It belongs
to the project rather than to any run, because the questions it holds
routinely outlive the unit that raised them, and because a note saying
"someone must own this next cycle" is worthless if it is filed somewhere
the next cycle is told not to read. Every role appends rows to it and cites
their ids; only a human ever closes one.

`<task-slug>` is a short kebab-case identifier for the task (e.g.
`add-csv-export`). Pick it once, at workspace creation, and use it
consistently — it's how every agent finds the right workspace.

**The whole workspace directory is gitignored, by policy.** Its contents
leave it three ways: `30_architecture.md`, `40_design_brief.md` and
`45_design_approval.md` are *promoted* into `docs/adr/` and `docs/design/`
as living documents; the verification evidence goes into the PR body; and
the whole workspace is *archived* verbatim to
`docs/archive/<YYYY-MM-DD>-<task-slug>/`, immutable, as the record of what
the inputs to this run were. Read `DOCUMENT-POLICY.md` before your first
run — it explains which documents carry an obligation to stay true, which
are deliberately frozen stale, and why a document-driven process fails when
that line isn't drawn.

**The order at the end is load-bearing: sign, then promote, then archive.**
Archiving first produces an immutable snapshot with a blank in it that the
human is expected to fill in later, which forces a choice between editing
the archive and never recording the approval at all. See
`DOCUMENT-POLICY.md`, "The order is part of the rule".

`45_design_approval.md` is the one artifact promoted somewhere other than
completion: it graduates at its own gate, before implementation starts,
because a design canon that arrives after the code is not a canon.

Numbering leaves gaps deliberately — `80` is unused, as are the intra-decade
slots — so an extra stage can be inserted later (a security review at `35`,
say) without renumbering everything else. `44` and `45` were inserted
exactly that way. Note that `70` is *not* a gap: `70_process_review.md`
sits there, off the main line, because the Process Advisor can run at any
point and gates nothing.

## Human gates — non-negotiable, enforced in the agent files themselves

These are not just documented here; each relevant agent's system prompt
(`agents/*.md`) repeats the specific rule so it's enforced structurally,
not just described in this doc:

1. **Plan approval.** `20_project_plan.md`'s `Approval Status` field
   starts at `PENDING_HUMAN_APPROVAL`. Only a human may change it to
   `APPROVED`, by editing the file directly. The Project Manager is
   explicitly instructed to never write `APPROVED` itself. The Solution
   Architect is explicitly instructed to check this field and refuse to
   proceed if it isn't exactly `APPROVED`.
2. **Design approval.** Same mechanism, on `45_design_approval.md`, and it
   applies whenever `20_project_plan.md` says `Design approval: required`.
   The Designer drafts the sheet with the Confirmed value column **empty**;
   the human fills it in and signs; the Developer refuses to implement
   until it reads `APPROVED`. **A missing sheet is a stop, not a skip** —
   the Developer may only proceed without one if it can quote the plan's
   line saying the gate was not required, so skipping it is always a
   decision someone made and can be held to.

   This gate exists because the Designer has no browser and no Bash. It
   cannot render or screenshot anything, so a design brief is prose, and
   prose is not a visual correct-answer however detailed it gets.
   Something has to be built and looked at before any visual requirement
   is verifiable at all — that is the mock round at `44_mock_build.md`,
   whose only reviewer is the human, at this gate.

   On approval the sheet is promoted to `docs/design/<slug>/README.md`
   straight away. It is a *different document* from the brief, and that is
   the point: a brief is written entirely in proposal voice, so promoting
   one as canon publishes a canon stating its own values are unconfirmed
   and listing the rejected options as though they were live. On the run
   that produced this gate, the Designer's ranking was C→B→A and the human
   chose A; a verbatim promotion would have left "recommended: C→B→A"
   sitting in canon next to an implementation using A, where the next agent
   to read it has every reason to "fix" the discrepancy in the wrong
   direction.
3. **Completion approval.** Same mechanism, on `90_completion.md`. The
   Project Manager drafts it after QA passes; only a human approves it.
   This gate is **evidence-based, not report-based**: `90_completion.md`
   carries an Evidence block (a screenshot of the running feature, a
   reachable instance holding real data, an end-to-end run, verbatim
   quality-gate output), and what the human is asked to do is *look at
   those and at the diff* — not read the summary and agree with it. A gate
   where a human reads a document and a document is all they get is not a
   gate; it degrades into acknowledging a green checkmark. "Was it built
   the way the plan said" is a conformance question the quality gates and
   self-review already cover. The human's review is for the question no
   machine can answer — is this the right thing — and that needs something
   to look at. See `DOCUMENT-POLICY.md`, "Approve artifacts, not reports."

   Nothing leaves the workspace until this field reads `APPROVED`. The
   human then invokes the Developer to promote and archive, in that order,
   and the archived copy carries the signature it already has.
4. **Closing an open decision.** `docs/OPEN-DECISIONS.md` rows are
   appended by any role and set to `CLOSED` only by a human, who also
   writes the Resolution. Same rule shape as `APPROVED`, and for the same
   reason: an agent that resolves its own open question has converted an
   undecided question into an unreviewed decision. Agents may add rows and
   add context to existing ones; they never close and never delete.
5. **All git write operations.** No agent in this harness ever runs
   `git commit`, `git push`, `git merge`, `git rebase`, `git reset`, or
   similar. Agents prepare a diff (by actually making the file changes),
   a suggested branch name, and a suggested commit message — a human runs
   the actual git commands. This is enforced two ways:
   - Every agent's system prompt states the rule explicitly under "What
     you must never do."
   - Agents with `Bash` access (`project-manager`, `solution-architect`,
     `developer`, `quality-assurance`) carry a `PreToolUse` hook
     (`hooks/block-git-write.sh`) that pattern-matches and blocks
     obviously mutating git subcommands and force flags at the tool-call
     level, regardless of what the agent was told to do. This is
     defense-in-depth, not the primary control — see "Setting up the git
     guardrail" below for the primary control.
6. **Irreversible/production-affecting actions.** Deploys, real (not
   test/staging) migrations, and secrets access are out of scope for
   every agent in this harness — they design for and describe these, they
   never execute them. Each agent's escalation triggers call this out.
7. **Strategic/scope-changing calls.** Any point where an agent notices
   the work implies a decision bigger than "how do we build the already-
   agreed-on thing" (roadmap calls, whether to support something at all,
   quietly expanding scope) is an explicit escalation trigger in the
   relevant agent's prompt — resolved by the human, never decided by the
   agent.
8. **Estimate overrun (>150% of plan).** The Developer is instructed to
   stop and flag `ESCALATION: ESTIMATE_OVERRUN` rather than keep working
   past this threshold. The Project Manager recomputes this flag every
   time it's re-invoked and surfaces it plainly.
9. **QA rejection loop cap (2 rework cycles).** The Developer gets two
   chances to rework a rejected implementation (revisions 2 and 3). If QA
   rejects revision 3 too — logged as `Rework cycle: 2` with verdict
   `REJECT`, meaning both rework chances are now used up — QA and the
   Project Manager both flag the pipeline as blocked pending a human
   decision. A revision 4 does not get attempted automatically; see "The
   QA rejection loop, precisely" below for the full walk-through.

## The QA rejection loop, precisely

- The Developer writes `50_implementation.md` with `Revision: 1`.
- QA reviews it and writes `60_qa_report.md` with
  `Reviewing implementation revision: 1` and a verdict.
- If REJECT: the Developer is re-invoked, addresses the listed defects,
  and rewrites `50_implementation.md` **in place** as `Revision: 2`
  (appending a Revision History entry, not deleting the prior one). QA is
  re-invoked and rewrites `60_qa_report.md` **in place** as
  `Rework cycle: 1`.
- If REJECT again: same pattern, `Revision: 3` / `Rework cycle: 2`. This
  is the cap. If QA still can't PASS revision 3, the pipeline stops here.
  A human must decide: extend the cap explicitly, re-scope via the
  Project Manager, or bring in a human developer. No agent extends the
  cap on its own initiative.
- If at any point QA's rejection reason traces to the architecture or
  design brief being wrong (not an implementation bug), QA is instructed
  to escalate rather than send it back to the Developer again — looping
  the Developer on a spec that's itself wrong just burns a rework cycle
  for nothing.

Files are revised **in place**, not as `50_implementation_v2.md` — this
keeps the numbered-pipeline convention simple (one file per stage) while
`STATUS.md`'s Event Log and each file's own Revision History preserve the
audit trail of what changed between attempts.

## Setting up the git guardrail (do this once per consuming project)

The `PreToolUse` hooks in `agents/project-manager.md`,
`agents/solution-architect.md`, `agents/developer.md`, and
`agents/quality-assurance.md` reference a script at
`.claude/hooks/claude-dev-team/block-git-write.sh` relative to the
consuming project's root. When you install this harness (see
`README.md`), copy `hooks/block-git-write.sh` from this repo to that path
and make it executable.

This hook is **defense-in-depth**, not the primary control — it's a
heuristic string match on Bash commands, not a real shell parser, so
treat it as a tripwire. The primary, stronger control is a
`permissions.deny` rule in the consuming project's
`.claude/settings.json`, which is enforced by Claude Code itself rather
than by pattern-matching a command string:

```json
{
  "permissions": {
    "deny": [
      "Bash(git commit:*)",
      "Bash(git push:*)",
      "Bash(git merge:*)",
      "Bash(git rebase:*)",
      "Bash(git reset:*)"
    ]
  }
}
```

Add both. See `README.md` for the full install steps.

## Running a task, turn by turn

This is the concrete walkthrough: what you actually type, in what order,
in your main Claude Code session, for one task from request to shipped
change. Assume a task slug of `add-csv-export` and that this harness is
already installed in the project (see `README.md`).

**1. Create the workspace and the request.**

```
mkdir -p .claude-dev-team/workspace/add-csv-export
```

Copy `templates/00_request.md` into that directory and fill it in
yourself — this is the one artifact in the pipeline you write directly,
not an agent. Keep it short: what you want, why, any hard constraints.

**2. Product brief.**

Type:
> Use the product-manager subagent to read
> .claude-dev-team/workspace/add-csv-export/00_request.md and write the
> product brief.

Check `10_product_brief.md`. If its Status is "Needs human input,"
resolve the Open Questions (edit the file, or just tell the agent the
answer and ask it to update the file) before continuing.

**3. Project plan — first human gate.**

Type:
> Use the project-manager subagent to write the project plan for
> add-csv-export.

Read `20_project_plan.md` yourself. This is a real gate — check the
breakdown and estimate make sense, check the Stages Required section
(does this task actually need a design brief?), check the risk register.
When you're satisfied, open the file and change:

```
**Approval Status:** PENDING_HUMAN_APPROVAL
```
to
```
**Approval Status:** APPROVED
```

Do not ask an agent to make this edit for you as a rubber stamp — this is
the point of the gate.

**4. Architecture.**

Type:
> Use the solution-architect subagent to write the architecture for
> add-csv-export.

It will itself check that `Approval Status: APPROVED` is present and
refuse to proceed if it isn't — that's a built-in check, not something you
need to remind it of. Review `30_architecture.md`.

**5. Design (only if the plan required it).**

Check `20_project_plan.md`'s Stages Required section. If Design is
"required":
> Use the designer subagent to write the design brief for
> add-csv-export.

It writes two files: `40_design_brief.md` (the proposal — options,
rationale, a recommendation) and `45_design_approval.md` (the decision
sheet, with the answers left blank for you).

If Design is "not required" / "N/A," skip straight to step 7.

**6. Design approval — second human gate.**

Read `40_design_brief.md`'s Visual SSOT status. It says one of two things,
and they lead to different next actions:

- **(b), no approved visual artifact exists.** Something has to be built
  and looked at before you can decide anything. Type:
  > Use the developer subagent to build the mock for add-csv-export.

  Say "build the mock" and not "implement" — the same subagent with a
  vaguer instruction will build the feature. It produces
  `44_mock_build.md`, whose "How to look at it" section gives you the
  command to run and the route to open. Run it. Actually look at it. That
  round never goes to QA; you are its reviewer.
- **(a), canon already exists** at `docs/design/<slug>/README.md`. No mock
  round. The sheet is short — it confirms the existing canon still governs
  and lists what it doesn't cover.

Then open `45_design_approval.md` and fill in the **Confirmed value**
column yourself, from what you saw. Fill in the Rejected proposals table
too — especially any case where you overruled the Designer's own
recommendation, because that is the one a later agent is most likely to
try to undo. Then sign it, the same way as step 3:

```
**Approval Status:** APPROVED
```

plus `Decided by` and `Decided on`. Then promote it:
> Use the developer subagent to promote 45_design_approval.md for
> add-csv-export.

This one promotion happens **now**, not at completion, because the
implementation that follows has to be able to read the canon it is being
built against. Everything else graduates at the end.

**7. Implementation.**

Type:
> Use the developer subagent to implement add-csv-export.

If the plan required design approval, the Developer checks that
`45_design_approval.md` reads `APPROVED` and refuses to proceed otherwise
— including when the file is simply absent. That is deliberate: a missing
approval sheet is a stop, never a silent skip.

This is the step that actually changes code in your project and runs
your real lint/test/build commands (as defined in your project's
`CLAUDE.md`). Review `50_implementation.md` — specifically the Quality
Gate Results section, verbatim, and the "Ready for QA" line.

**8. QA — independent verification.**

Type:
> Use the quality-assurance subagent to review add-csv-export.

Read `60_qa_report.md`. If the verdict is REJECT and the rework cap
isn't reached, go back to step 7 (the Developer will read the QA report
and address the defects). If PASS, continue.

If the report shows `Rework cycle: 2` with verdict REJECT (i.e., revision
3 — the Developer's second and final allowed rework attempt — still
failed QA, so the cap is reached), or if QA says the problem traces to
the architecture rather than the implementation: don't re-invoke the
Developer a fourth time on your own. Decide yourself (or re-invoke the
project-manager subagent to help you think it through) whether to
re-scope, go back to the Solution Architect, or extend the cap knowingly.

**9. Completion — third human gate.**

Once QA shows PASS:
> Use the project-manager subagent to draft the completion summary for
> add-csv-export.

Read `90_completion.md` — but **read the Evidence block first**, before the
prose, and actually open the things it points at. Then review the real diff
yourself. The summary is not a substitute for either. If the Evidence block
has rows marked MISSING, that is the finding: decide whether to accept the
gap knowingly or send it back, and don't let a confident summary stand in
for the artifact you couldn't see.

Check the "Open decisions for this task" line against
`docs/OPEN-DECISIONS.md`. Anything still `OPEN` is something you are about
to ship undecided. Close the rows you can answer — you are the only one who
may — and knowingly accept the rest.

**Then sign, and only then promote.** Edit `Approval Status` to `APPROVED`,
exactly as in step 3.

**10. Promote and archive — after the signature, never before.**

> Use the developer subagent to promote and archive add-csv-export.

The Developer checks that the gate above reads `APPROVED` and refuses
otherwise. It promotes each row in the table, marking it `done`, and
archives the workspace last. The archive row stays `pending` — nothing can
mark itself done inside the copy it is making; its truth is the directory
existing.

The order is not fussiness. Archive first and the snapshot contains a blank
you are expected to fill in later, which leaves you choosing between editing
an immutable archive and never recording your approval anywhere. On the run
that produced this rule, the workspace was archived first and the signature
went into the archive — and an edited archive looks exactly like an unedited
one, so nothing would ever have flagged it.

Do not skip the archive on the grounds that the task went smoothly. The
archive is the only record of *what the inputs to this run were*, and its
value is realised at the retrospective, not now — by which point the choice
to skip it is unrecoverable. A diff records the output; nothing records the
input unless you keep it.

Then check the work was actually done:

```
scripts/claude-dev-team/verify-dev-team.sh --slug add-csv-export
```

**11. Ship it — you run this, not an agent.**

```
git checkout -b <the suggested branch name>
git add <the files 50_implementation.md listed, plus the promoted files>
git commit -m "<the suggested commit message, edited if you want>"
git push
```

Then open the PR and **paste `90_completion.md`'s "What was delivered",
"Evidence", and "Outstanding follow-ups" sections into the PR
description.** This is not ceremony: the workspace is gitignored, so the PR
body and the commit history are the only places this evidence survives, and
they are what lets someone verify this completion claim months from now
without you. See `DOCUMENT-POLICY.md`.

Add one line to the PR body, anywhere:

```
Dev-Team-Run: add-csv-export
```

That is how CI knows which runs this change carries — it cannot see the
workspace, which is gitignored. Write `Dev-Team-Run: none` for a change
that did not come from the pipeline at all. See "Verifying a run" below.

No agent in this harness will do this step for you, by design.

**12. Optional: process review.**

At any point — after completion, after a rejection cycle that bugged you,
or mid-task if something about how the team is working feels off:
> Use the process-advisor subagent to review add-csv-export.

This never blocks anything. Read `70_process_review.md` when you want
candid feedback on the process itself, separate from the product.

## STATUS.md — the run's timeline

`STATUS.md` is created by the Project Manager alongside `20_project_plan.md`
and updated on every re-invocation. It has exactly two parts, and the
division between them is the whole design:

- **The Event Log** is append-only and authoritative. Every role may
  append; nobody edits or deletes an existing entry. A wrong entry is
  corrected by appending a correction, never by fixing it in place.
- **The Derived Summary** is a cache, recomputed from the log on every
  read, and each field cites the log entries it came from so a reader can
  falsify it in seconds. If the summary and the log disagree, the log is
  right.

This shape exists because the alternative failed in the field: overwritten
status fields, in a single-person project with no concurrent writers,
drifted out of agreement with reality and reported a completed build that
did not exist. An overwrite destroys the previous value, so a wrong write
leaves no trace and reads exactly like a right one.

Two things `STATUS.md` is not. It is **not a gate** — approval lives in
`20_project_plan.md`, `45_design_approval.md` and `90_completion.md`, in
fields only a human may set; this file records that approval happened, it
never constitutes it. And it is **not where open questions live** — those
are rows in `docs/OPEN-DECISIONS.md`, and an escalation entry in the log
cites the id of the row it raised. `STATUS.md` answers *what happened
when*; the ledger answers *what is still open*. The split matters because
`STATUS.md` is archived at completion and the ledger is not: an open
question recorded only here becomes unreachable at exactly the moment the
next unit starts.

Full field-by-field template, with the rules stated inline:
`templates/STATUS.md`.

## Verifying a run

`scripts/verify-dev-team.sh` checks that a run left the record it was
supposed to leave. Install it into the consuming project (see `README.md`)
and wire the sample workflow at
`examples/github/claude-dev-team-verify.yml` so it runs on every PR.

It is not a Claude Code hook. `hooks/block-git-write.sh` matches a command
string at tool-call time; this reads the filesystem and `git diff` at
review time. Different shape, different install path, no shared code.

What it checks, in three groups:

| Group | Question |
|---|---|
| `A0`–`A6` | Was the run archived at all, is every required artifact in it, was every gate signed before the snapshot was taken, and has nothing in `docs/archive/` been modified since? |
| `B1`–`B3` | Did promotion actually run, do the promoted destinations exist, and does every design canon carry the `README.md` that makes it canon rather than a proposal? |
| `C1`–`C4` | Does every cited `OD-` id resolve to a ledger row, are the ids unique, and has no row been deleted? |

Two of these are worth calling out because nothing enforced them before.
`A3` greps the archive for `PENDING_HUMAN_APPROVAL`, which is the
mechanical form of the invariant **no archived file may contain a field
anyone is expected to fill in later**. `A6` asserts that the diff touching
`docs/archive/` contains only additions, which is the first time
"immutable once written" has been anything other than a sentence.

**How it knows which runs a PR carries — and the honest limit.** The
workspace is gitignored, so CI cannot see a run in flight. The script
therefore asks the PR to declare its runs (`Dev-Team-Run: <slug>`, or
`Dev-Team-Run: none`), falling back to any archive directory it can see
added in the diff. That is a self-report, and it cannot catch a pipeline
run that left no trace at all. What it does catch is the case that
actually happened — a run that produced artifacts and then dropped them —
and it converts an omission from silence into a line a reviewer can see.
Do not present it as airtight.

Quality Assurance also runs a cheaper preflight mid-pipeline:

```
scripts/claude-dev-team/verify-dev-team.sh --workspace .claude-dev-team/workspace/add-csv-export
```

which catches unfilled placeholders and dangling ledger ids while the
workspace still exists to fix them in. It deliberately does *not* check for
unsigned gates: in a live workspace, an unsigned gate is the correct state.

## Resuming a broken or interrupted task

Because every handoff is a file, not conversation state, you can pick a
task back up in a brand-new Claude Code session at any time: open the task
workspace, read `STATUS.md`'s Event Log — the log itself, not the summary
above it — and re-invoke whichever agent produces the next artifact.
Nothing about this pipeline depends on a single long-running session.

## Advanced: letting the Project Manager drive

If you want less manual invocation once you're comfortable with the
pipeline: run `claude --agent project-manager` to make an entire session
run as the Project Manager. In that mode the Project Manager's system
prompt becomes the session's system prompt, and — because it's now the
main thread, not a subagent — it has access to the `Agent` tool and could
spawn the other roles directly rather than just telling you what to run.

This harness does not assume you'll do this, and the Project Manager's
own prompt (`agents/project-manager.md`) is deliberately written to give
you a "Next:" instruction either way, so the manual and the automated
patterns both work with the same files. If you do try this pattern, keep
the human gates (steps 3, 6 and 9 above) as manual edits regardless — that's
the part that must stay a real human action, not something to automate
away even in this mode.

## Known limitations of this pipeline (see also CHANGELOG.md)

- The rejection-loop cap and the estimate-overrun threshold are tracked by
  agents reading and reasoning over markdown files, not by a hard external
  counter. A careless or confused invocation could in principle miscount
  a revision number. Treat `STATUS.md`'s Event Log as the source of truth
  if an agent's count ever looks wrong, and don't hesitate to intervene
  manually.
- The `block-git-write.sh` hook is a heuristic pattern match, not a shell
  parser — see its own comments and the "Setting up the git guardrail"
  section above for why the `permissions.deny` rule is the control that
  actually matters.
- Tool permissions in Claude Code are granted per-tool, not per-path —
  there's no frontmatter-level way to say "QA can Write to
  60_qa_report.md but not to source files." QA's own prompt instructs it
  never to edit source, but that's an instruction, not a structural
  barrier the way the git hook is. If your project needs a harder
  guarantee, consider a `permissions.deny` rule scoped to your source
  directories for the `quality-assurance` agent specifically.
- `verify-dev-team.sh` learns which runs a PR carries from a
  `Dev-Team-Run:` line the human writes. Because the workspace is
  gitignored, a run that produced nothing leaves nothing for CI to notice,
  so the check cannot catch a pipeline run that was abandoned without
  trace. It catches the failure that actually occurred — artifacts
  produced and then dropped — and makes omission visible rather than
  silent. Treat it as a floor, not a proof.
- The design-approval gate adds real ceremony: a third gate, and for a new
  visual surface a mock round before implementation. The cheap path is
  deliberate — when canon already exists, `45_design_approval.md` is a
  one-row sheet confirming it still governs. But that path has to stay a
  *positive statement* in the plan. The moment "no visual surface" becomes
  something an agent infers rather than something a human wrote down, the
  gate is dead and you are back to approving screenshots after the fact.
