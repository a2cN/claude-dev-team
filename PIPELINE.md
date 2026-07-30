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
40_design_brief.md      <- Designer                    (skipped otherwise)
   |
   v
50_implementation.md    <- Developer         <---+
   |                                              |
   v                                              | REJECT (rework, capped at 2 cycles)
60_qa_report.md          <- Quality Assurance -----+
   |
   v PASS
90_completion.md         <- Project Manager            } HUMAN GATE: completion approval,
                                                          incl. the actual git commit/push

70_process_review.md    <- Process Advisor (optional, any time, doesn't gate anything)
```

Every artifact lives in one task workspace:

```
.claude-dev-team/workspace/<task-slug>/
  00_request.md
  10_product_brief.md
  20_project_plan.md
  STATUS.md
  30_architecture.md
  40_design_brief.md        (only if Design is required)
  50_implementation.md      (revised in place across rework cycles)
  60_qa_report.md           (revised in place across rework cycles)
  70_process_review.md      (optional, any point)
  90_completion.md
```

`<task-slug>` is a short kebab-case identifier for the task (e.g.
`add-csv-export`). Pick it once, at workspace creation, and use it
consistently — it's how every agent finds the right workspace.

**The whole workspace directory is gitignored, by policy.** At completion
its contents leave it three ways: `30_architecture.md` and
`40_design_brief.md` are *promoted* into `docs/adr/` and `docs/design/` as
living documents; the verification evidence goes into the PR body; and the
whole workspace is *archived* verbatim to
`docs/archive/<YYYY-MM-DD>-<task-slug>/`, immutable, as the record of what
the inputs to this run were. Read `DOCUMENT-POLICY.md` before your first
run — it explains which documents carry an obligation to stay true, which
are deliberately frozen stale, and why a document-driven process fails when
that line isn't drawn.

Numbering leaves gaps (there is no `70` in the main line, `80` is unused)
deliberately, matching the original design this harness is based on: it
leaves room to insert an extra stage later (e.g. a security-review stage
at `35`) without renumbering everything else.

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
2. **Completion approval.** Same mechanism, on `90_completion.md`. The
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
3. **All git write operations.** No agent in this harness ever runs
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
4. **Irreversible/production-affecting actions.** Deploys, real (not
   test/staging) migrations, and secrets access are out of scope for
   every agent in this harness — they design for and describe these, they
   never execute them. Each agent's escalation triggers call this out.
5. **Strategic/scope-changing calls.** Any point where an agent notices
   the work implies a decision bigger than "how do we build the already-
   agreed-on thing" (roadmap calls, whether to support something at all,
   quietly expanding scope) is an explicit escalation trigger in the
   relevant agent's prompt — resolved by the human, never decided by the
   agent.
6. **Estimate overrun (>150% of plan).** The Developer is instructed to
   stop and flag `ESCALATION: ESTIMATE_OVERRUN` rather than keep working
   past this threshold. The Project Manager recomputes this flag every
   time it's re-invoked and surfaces it plainly.
7. **QA rejection loop cap (2 rework cycles).** The Developer gets two
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

If Design is "not required" / "N/A," skip straight to step 6.

**6. Implementation.**

Type:
> Use the developer subagent to implement add-csv-export.

This is the step that actually changes code in your project and runs
your real lint/test/build commands (as defined in your project's
`CLAUDE.md`). Review `50_implementation.md` — specifically the Quality
Gate Results section, verbatim, and the "Ready for QA" line.

**7. QA — independent verification.**

Type:
> Use the quality-assurance subagent to review add-csv-export.

Read `60_qa_report.md`. If the verdict is REJECT and the rework cap
isn't reached, go back to step 6 (the Developer will read the QA report
and address the defects). If PASS, continue.

If the report shows `Rework cycle: 2` with verdict REJECT (i.e., revision
3 — the Developer's second and final allowed rework attempt — still
failed QA, so the cap is reached), or if QA says the problem traces to
the architecture rather than the implementation: don't re-invoke the
Developer a fourth time on your own. Decide yourself (or re-invoke the
project-manager subagent to help you think it through) whether to
re-scope, go back to the Solution Architect, or extend the cap knowingly.

**8. Completion — second human gate.**

Once QA shows PASS:
> Use the project-manager subagent to draft the completion summary for
> add-csv-export.

Read `90_completion.md` — but **read the Evidence block first**, before the
prose, and actually open the things it points at. Then review the real diff
yourself. The summary is not a substitute for either. If the Evidence block
has rows marked MISSING, that is the finding: decide whether to accept the
gap knowingly or send it back, and don't let a confident summary stand in
for the artifact you couldn't see.

Also check the "Artifacts due for promotion and archiving" table. If rows
are still `pending`, nothing has left the workspace yet and it will all be
lost at merge, because the workspace isn't committed:

> Use the developer subagent to promote and archive the artifacts listed in
> 90_completion.md for add-csv-export.

Do not skip the archive row on the grounds that the task went smoothly. The
archive is the only record of *what the inputs to this run were*, and its
value is realised at the retrospective, not now — by which point the choice
to skip it is unrecoverable. A diff records the output; nothing records the
input unless you keep it.

When satisfied, edit `Approval Status` to `APPROVED`, exactly as in step 3.

**9. Ship it — you run this, not an agent.**

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

No agent in this harness will do this step for you, by design.

**10. Optional: process review.**

At any point — after completion, after a rejection cycle that bugged you,
or mid-task if something about how the team is working feels off:
> Use the process-advisor subagent to review add-csv-export.

This never blocks anything. Read `70_process_review.md` when you want
candid feedback on the process itself, separate from the product.

## Resuming a broken or interrupted task

Because every handoff is a file, not conversation state, you can pick a
task back up in a brand-new Claude Code session at any time: open the
task workspace, check `STATUS.md`'s Current Stage, and re-invoke whichever
agent produces the next artifact. Nothing about this pipeline depends on
a single long-running session.

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
the human gates (steps 3 and 8 above) as manual edits regardless — that's
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
