<!--
  Template for STATUS.md — the running tracker for one task workspace.
  Lives at:
    .claude-dev-team/workspace/<task-slug>/STATUS.md

  Unlike the numbered NN_*.md artifacts, this file is NOT a one-time
  handoff — it is a live log that the Project Manager agent creates the
  first time it runs (when it writes 20_project_plan.md) and updates every
  time it is re-invoked. Other roles may also append a one-line entry to
  the Event Log when something status-worthy happens (a rejection, an
  escalation), but only the Project Manager rewrites the summary fields at
  the top.

  This file is what answers "where are we?" without anyone needing to
  re-read every artifact from scratch.
-->

# Status: <task-slug>

**Current stage:** <e.g. "Awaiting plan approval" / "In development" /
  "In QA — rework cycle 1" / "Awaiting completion approval" / "Complete">
**Stages required this task:** Product [x] · Project Plan [x] ·
  Architecture [x] · Design [ / N/A] · Development [ ] · QA [ ] ·
  Completion [ ]
**Original estimate (from 20_project_plan.md):** <e.g. "3 dev-days">
**Actual effort logged so far:** <running total, updated by PM>
**Estimate-overrun flag (>150% of original):** NO / YES — see Event Log

**Rework cycles used:** 0 / 2 max (Developer <-> QA loop; see PIPELINE.md
  for the cap rule)

**Open escalations:** NONE / <list, each with the artifact and human gate
  it's waiting on>

**Human gate log:**
| Gate | Artifact | Status | Decided by | Date |
|---|---|---|---|---|
| Plan approval | 20_project_plan.md | PENDING | — | — |
| Completion approval | 90_completion.md | — | — | — |

## Event Log

<Reverse-chronological. One line per event. Every role may append; only
the Project Manager edits the summary fields above.>

- <YYYY-MM-DD> — Workspace created, 00_request.md received.
