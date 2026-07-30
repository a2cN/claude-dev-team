<!--
  Template for STATUS.md — the running tracker for one task workspace.
  Lives at:
    .claude-dev-team/workspace/<task-slug>/STATUS.md

  This file is TRANSIENT and is not committed (see DOCUMENT-POLICY.md).
  Its value expires when the change merges.

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
  3. Nothing here is a gate. Approval lives in `20_project_plan.md` and
     `90_completion.md`, in fields only a human may set to APPROVED. This
     file records that it happened; it never constitutes it.
-->

# Status: <task-slug>

## Event Log (append-only, chronological, authoritative)

<!--
  One line per event, oldest first. Append at the bottom.
  Format: <YYYY-MM-DD> — <ROLE> — <what happened>

  Log an entry for at least: workspace creation, each artifact written
  (with its revision number), each QA verdict, each human gate decision,
  each escalation raised and resolved, and any effort figure reported.
  Include the numbers themselves — a later reader must be able to count
  rework cycles and total effort from this log alone, without opening
  another file.
-->

- <YYYY-MM-DD> — HUMAN — Workspace created; `00_request.md` written.

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

**Effort logged:** <sum of effort figures appearing in the log>
_derived from:_ <entries carrying effort figures>

**Estimate:** <total from `20_project_plan.md`>
**Overrun threshold (150%):** <computed>
**Overrun status:** WITHIN / EXCEEDED — <or "cannot determine from log">

**Human gates:** <for each gate, its state as most recently logged>
- Plan approval (`20_project_plan.md`): <PENDING / APPROVED on YYYY-MM-DD by HUMAN / REJECTED>
- Completion approval (`90_completion.md`): <not yet reached / PENDING / APPROVED …>
_derived from:_ <log entries>

**Open escalations:** <those raised in the log with no matching resolution entry>
_derived from:_ <log entries>
