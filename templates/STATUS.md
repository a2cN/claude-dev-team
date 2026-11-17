<!--
  Template for STATUS.md — the running tracker for one task workspace.
  Lives at:
    .claude-dev-team/workspace/<task-slug>/STATUS.md

  This file is TRANSIENT in the working tree and is not committed there
  (the whole workspace is gitignored). It is NOT discarded: at completion
  it is archived verbatim to docs/archive/<YYYY-MM-DD>-<task-slug>/ along
  with the rest of the workspace, because the Event Log is the timeline of
  the run and a retrospective needs it. See DOCUMENT-POLICY.md,
  "Per-artifact ruling".

  What expires at merge is its authority, not its existence. After
  archiving, nothing here is a source of truth for implementation — and
  anything that must remain actionable for a *later* unit does not belong
  here at all. It belongs in docs/OPEN-DECISIONS.md, which is not archived.

  ============================================================
  READ THIS BEFORE EDITING: the Event Log is the only authority
  ============================================================

  Earlier versions of this template had mutable summary fields at the top
  that the Project Manager overwrote on every re-invocation ("Current
  stage: ...", "Rework cycles used: 1 / 2", a human-gate table whose rows
  were rewritten in place). That design is retired, because it is the exact
  shape that failed in the field: in a single-person project with no
  concurrent writers, overwritten status fields drifted out of agreement
  with reality and reported a completed build that did not exist. An
  overwrite destroys the previous value, so a wrong write leaves no trace
  and is indistinguishable from a right one.

  So:

  1. The **Event Log is append-only and is the source of truth.** Every
     role may append. Nobody edits or deletes an existing entry. If an
     earlier entry was wrong, append a correction — do not fix it in place.
  2. The **Derived Summary is recomputed, not maintained.** It is a cache
     of what the Event Log already says. Whoever writes it must cite the
     entries it came from, so a reader can falsify it in seconds. If the
     summary and the log disagree, **the log is right.**
  3. Nothing here is a gate. Approval lives in `20_project_plan.md`,
     `45_design_approval.md` and `90_completion.md`, in fields only a human
     may set to APPROVED. This file records that it happened; it never
     constitutes it.
  4. **Open questions are not stored here.** They live as rows in
     `docs/OPEN-DECISIONS.md`. An escalation entry in the log below cites
     the id of the row it raised, and the Open escalations field is derived
     from the ledger. This file answers *what happened when*; the ledger
     answers *what is still open*.
-->

# Status: <task-slug>

## Event Log (append-only, chronological, authoritative)

<!--
  One line per event, oldest first. Append at the bottom. Full design:
  design/measurement.md in the harness repo (section 4).

  Format:
    - <time> — <ROLE> — <event> <key=value ...> [— <free text>]

  <time> is ISO 8601 to the second with a zone, taken from the shell
  (`date -Iseconds`), never written from memory: a model does not know
  the time, and the run window below is cut on these times.
  Roles with no shell (product-manager, designer) write the date only,
  <YYYY-MM-DD>; the line order still gives the sequence, and the times the
  run window is cut on (run-start, run-end) come from the ORCHESTRATOR.
  Values contain no spaces; free text goes after the last " — ".
  `verify-dev-team.sh --workspace` (A7) fails when a time goes backwards
  or into the future. Fix it by appending a `correction ref=<the wrong
  time>` line, never by editing the line.
  A line with no recognised <event> is still allowed — it is read by
  humans and ignored by counting.

  Events (role that writes it — required keys):
    run-start   ORCHESTRATOR  run=<task-slug>-<n>
    stage-start ORCHESTRATOR  stage=<role> rev=<n>
    stage-end   ORCHESTRATOR  stage=<role> rev=<n> outcome=ok|blocked|escalated
    verdict     QA            rev=<n> result=PASS|REJECT tags=<tag>:<n>,...
    gate        HUMAN         gate=plan|design|completion result=APPROVED|REJECTED|REVIEWED
    escalate    any           trigger=od|rework-cap|token-budget|contradiction|protected-path|no-mock ref=<id>
    human-fix   HUMAN         what=code|doc|config
    tokens      ORCHESTRATOR  pasted from token-report.py (below)
    model-check ORCHESTRATOR  pasted from token-report.py (below) — result=match|mismatch|unspecified per stage
    run-end     ORCHESTRATOR  run=<task-slug>-<n> outcome=done|abandoned
    correction  any           ref=<time of the line being corrected>

  Log at least: run-start and run-end, each artifact written (with its
  revision number), each QA verdict, each human gate decision, each
  escalation raised and resolved, each promotion and the archive. Include
  the numbers themselves — a later reader must be able to count rework
  cycles and tokens from this log alone, without opening another file.

  An escalation must cite the ledger id of the row it raised in ref=, e.g.
  "escalate trigger=od ref=OD-add-csv-export-02 — accent colour undecided".
  The id is what lets a reader join this timeline to
  docs/OPEN-DECISIONS.md; an escalation logged without one is unfindable
  the moment this workspace is archived.

  QA verdicts carry their failure-tag counts (agents/quality-assurance.md,
  "Failure tags"), e.g. "verdict rev=2 result=REJECT tags=spec:1,impl-bug:2".

  Tokens are never estimated by an agent. At run-end, the ORCHESTRATOR
  runs, over the run's session transcripts (see LOGGING.md):
    python3 scripts/claude-dev-team/token-report.py <session>.jsonl \
        --since <run-start time> --until <run-end time> --format log
  and appends each output line as its own `tokens` / `model-check` entry.
  That gives one line per stage (one per subagent invocation), one for the
  orchestrator itself, and one for the whole run, then the same three
  scopes again comparing each stage's model with its definition's
  `model:`. Required: session transcripts are
  deleted by Claude Code after 30 days by default, and a run whose tokens
  were not logged by then cannot be measured at all.
  Counts only — never transcript content.
-->

- <time> — HUMAN — Workspace created; `00_request.md` written.
- <time> — ORCHESTRATOR — run-start run=<task-slug>-1

## Derived Summary (recomputed on every read — never hand-maintained)

<!--
  Recompute every field from the Event Log above. Cite the log entries
  used, by date and role. Write "cannot determine from log" rather than
  guessing — an honest gap is useful, an invented value is not.
-->

**Current stage:** <derived — from the most recent artifact-written entry>
_derived from:_ <log entries>

**Stages required:** <copied from `20_project_plan.md`'s Stages Required —
  that file is the authority for this one field, not this log>

**Rework cycles used:** <count of QA REJECT verdicts in the log> / 2 max
_derived from:_ <the specific REJECT entries, by date>
<!-- The cap is reached at rework cycle 2 paired with a REJECT — i.e.
     revision 3, the final allowed attempt, failed QA. Then the pipeline
     is blocked pending a human decision. -->

**Failure tags across REJECTs:** <spec=n, misalignment=n, verification=n, impl-bug=n — summed from the QA entries>
_derived from:_ <the `verdict ... result=REJECT` entries, by time>

**Tokens (whole run):** <copied from the `tokens scope=run` entry: ieq, and the five raw counts — or "not yet logged">
**Heaviest stage:** <the `tokens scope=stage` entry with the largest ieq: stage, rev, ieq>
_derived from:_ <those entries>
<!-- Do not add the stage entries together to fill the whole-run field:
     the orchestrator's own line is part of the run too. The scope=run line
     is the total. -->

**Effort logged:** <sum of effort figures appearing in the log>
_derived from:_ <entries carrying effort figures>

**Estimate:** <total from `20_project_plan.md`>
**Overrun threshold (150%):** <computed>
**Overrun status:** WITHIN / EXCEEDED — <or "cannot determine from log">

**Human gates:** <for each gate, its state as most recently logged>
- Plan approval (`20_project_plan.md`): <PENDING / APPROVED on YYYY-MM-DD by HUMAN / REJECTED>
- Design approval (`45_design_approval.md`): <not required per the plan / not yet reached / PENDING / APPROVED …>
- Completion approval (`90_completion.md`): <not yet reached / PENDING / APPROVED …>
_derived from:_ <log entries>

**Open escalations:** <rows in `docs/OPEN-DECISIONS.md` whose Task slug is
  this one and whose Status is OPEN, listed by id>
_derived from:_ <the ledger rows, cross-checked against the log entries citing those ids>
<!-- If the log cites an id that is not in the ledger, or the ledger holds
     an OPEN row for this slug that the log never mentions, say so here
     rather than picking one. That disagreement is a finding: it means an
     open question exists in exactly one of the two places that are
     supposed to agree, and it is about to be archived. -->

**Promotion and archive:** <not yet reached / promoted on YYYY-MM-DD / archived on YYYY-MM-DD>
_derived from:_ <log entries>
<!-- These happen only after the completion gate is APPROVED, in that
     order. See DOCUMENT-POLICY.md, "The order is part of the rule". -->
