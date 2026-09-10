<!--
  Template for the open-decisions ledger.
  Lives at:
    docs/OPEN-DECISIONS.md

  Copy this file there once, per project, and commit it. Unlike everything
  in .claude-dev-team/workspace/, this file is NOT transient and is NOT
  archived: it belongs to the project, not to a run, because the questions
  it holds routinely outlive the unit that raised them.

  ============================================================
  READ THIS BEFORE EDITING
  ============================================================

  This ledger exists because open questions used to live in five places at
  once. On the run that motivated it, a human at the completion gate asked
  "what is still undecided?" and the honest answer required reading five
  artifacts whose lists disagreed: the completion summary said three, the
  union was six, and the two it dropped were live design values that would
  have shipped as whatever the implementer happened to pick.

  So there is one list, and the artifacts cite it instead of restating it.

  1. **Rows are created only here.** An artifact that has an open question
     appends a row to this table and then cites its id. It does not keep a
     parallel list of its own. "How many are open" is `grep -c`, not a
     reconciliation.

  2. **Only a human may write CLOSED**, and only a human may write the
     Resolution cell. This is the same rule, with the same reasoning, as
     `Approval Status: APPROVED` in `20_project_plan.md`,
     `45_design_approval.md` and `90_completion.md`. An agent that resolves
     its own open question has converted an undecided question into an
     unreviewed decision, which is the failure this whole harness is built
     against.

  3. **Agents append; they never delete.** Adding context to an existing
     row is fine — append it to the Decision needed cell, or add a log
     entry in the run's STATUS.md citing the id. Removing a row, rewording
     someone else's row, or narrowing an option list is not.

  4. **Ids are `OD-<task-slug>-NN`**, two digits, allocated by grepping
     this file for rows with your own task slug and taking the next number.
     Scoping ids to the slug means two live workspaces cannot collide, and
     an agent never has to read rows that are not its business.

  5. **A row outliving its unit is the point, not a leak.** When a
     workspace is archived, its OPEN rows stay OPEN here. They are the next
     unit's inputs. Nothing migrates, so nothing can be forgotten in the
     migration.

  6. **Relationship to STATUS.md:** that file's Event Log stays the
     authority for *what happened when*, and every escalation entry in it
     cites the id of the row it raised. This ledger is the authority for
     *what is still open*. Two authorities over the same fact would be the
     bug this table was written to fix; two authorities over different
     facts, joined by an id, is a foreign key.

  Column notes:
    Options / default if unanswered — what happens if nobody decides. If
      the honest answer is "the implementer picks something plausible",
      write that. It is the sentence most likely to get the row closed.
    Blocks — what cannot correctly proceed until this is closed. Empty is
      a legitimate answer; a question that blocks nothing is still worth
      recording, it just isn't urgent.
    Resolution — human only. What was decided, who decided it, and the
      date. Not "done".

  A filled row looks like this (kept in this comment, not in the table, so
  that the table starts genuinely empty and no checker mistakes an example
  for a real open question):

    | OD-add-csv-export-01 | 2026-07-31 | DESIGNER | add-csv-export |
      Accent colour for the export button | A (existing brand blue),
      B (neutral grey), C (green); recommend C. If nobody answers, the
      implementer picks one and it ships unreviewed. | 45_design_approval.md |
      OPEN | |
-->

# Open Decisions

Questions this project has not answered yet, and the record of how the
answered ones were settled. One row per question. **Only a human may set a
row to `CLOSED` or write its Resolution.**

Every agent role in `.claude/agents/` appends to this file and cites the ids
it appended; no artifact keeps its own separate list of open items. See
`DOCUMENT-POLICY.md`, "One ledger for open decisions".

| ID | Raised | By | Task slug | Decision needed | Options / default if unanswered | Blocks | Status | Resolution (human only) |
|---|---|---|---|---|---|---|---|---|
