# Design Notes / Changelog

## v1.0.0 — initial design

First build of this harness: 7 roles, file-based pipeline, human gates,
git-write guardrail. This section records the decisions made and why,
for whoever maintains this template next.

### Why 7 roles, and why these 7

Kept the same headcount as the reference design this is based on, but
renamed one role and re-scoped its purpose. The original's "EM Support"
role was framed around org/mentoring concerns, which don't map cleanly
onto a small AI dev team that has no career ladder, no 1:1s, and no
people to mentor. What *does* map is the underlying need that role was
serving: someone whose job is to say the uncomfortable thing about how
the team is functioning, with no stake in defending any of the work. That
became **Process Advisor** — reviews the process (plan realism, rework
loop causes, human-gate load), never the product, and has zero gating
authority so it can't become a bottleneck or a rubber stamp.

### Why file-based handoff instead of trying to make agents call each other

This was a given from the brief, but worth recording why it's the right
call independent of that: Claude Code subagents cannot chain-invoke each
other reliably or auditably enough to build a multi-hour, resumable,
human-gated pipeline on top of. Even where nested subagent spawning is
technically possible (see `PIPELINE.md`'s note on `claude --agent
project-manager`), building the *default* pattern around it would make
this harness fragile in exactly the way it's supposed to be robust:
resumable after an interrupted session, auditable by a human at any
intermediate point, and cheap to run because each role only reads the
artifacts it needs rather than a full conversation transcript. Markdown
files in a workspace directory get all three for free.

### Why revise-in-place for 50/60 instead of numbered sub-revisions

Considered `50_implementation_v2.md`, `50_implementation_v3.md`, etc.
Rejected it: it breaks the "one file per pipeline stage" mental model the
numbering is supposed to give you, and it means QA has to figure out
which implementation file is current rather than just reading
`50_implementation.md`. Revising in place with an explicit `Revision:`
field and an appended Revision History section keeps the audit trail
(what changed between attempts) without multiplying files. `STATUS.md`'s
Event Log is the redundant backstop if a revision number ever gets
miscounted.

### Why the git-write guardrail is both a hook AND a settings.json rule

A `PreToolUse` hook that pattern-matches Bash commands is genuinely
useful, but it's a heuristic string match, not a real shell parser — it
can be fooled by a command it doesn't recognize as git (a wrapper script,
an alias, a language runtime shelling out). `permissions.deny` rules in
`.claude/settings.json` are enforced by Claude Code's actual permission
system, not by pattern-matching a string, so they're the stronger
control. Shipping only the hook would have looked structural while
actually being softer than it appears; shipping only the settings.json
recommendation would mean a project that skips that one setup step (easy
to forget, since it lives outside this harness's own files) has *no*
structural guardrail at all, just the system-prompt instruction. Both,
layered, was the only option that didn't have an obvious single point of
failure.

### Why QA gets Write but not Edit

QA needs to produce and revise `60_qa_report.md` across rework cycles,
which requires some write capability. Giving it `Edit` as well felt like
an invitation to "just fix this one small thing" directly in source,
which is exactly the failure mode that makes independent QA meaningless
(see the Developer/QA separation-of-duties principle). `Write` lets QA
overwrite its own report file; it doesn't make patching source any more
convenient than `Read`+`Bash` already would in a pinch, and the system
prompt's explicit "never fix the implementation yourself" instruction
does the rest. This is a soft control, not a hard one — see "Known
limitations" below.

### Why Designer is conditional rather than always-on

Not every task has a user-facing surface (backend migrations, internal
scripts, API-only changes). Making Designer mandatory would either waste
a stage on every non-UI task or train operators to skip stages casually,
which erodes the discipline the rest of the pipeline depends on. Instead,
the Project Manager decides and records the answer explicitly in
`20_project_plan.md`'s Stages Required section at plan time, so the
decision is auditable and made once, deliberately, rather than
re-litigated ad hoc at each stage.

### Why the rework cap is 2, and why it's enforced by instruction rather than a hard mechanism

Matched the reference design's cap. Chose to enforce it through explicit,
repeated instruction in both the Developer's and QA's system prompts
(both count revisions from the artifacts themselves and are told plainly
what happens at the cap) rather than trying to build a hard mechanical
stop. Claude Code's `maxTurns` frontmatter field caps turns *within* a
single subagent invocation, not across multiple separate invocations over
a rework loop spanning several human-triggered calls — there's no
frontmatter field that caps "how many times has this workspace's implementation
file been rejected." This is a real limitation (see below), mitigated by
having both the Developer, QA, and the Project Manager independently
count and cross-check the same number from the same files, so a single
miscounting agent doesn't silently blow past the cap unnoticed.

### Why model tiers are pinned to `opus`/`sonnet` explicitly rather than `inherit`

`inherit` would make every agent run at whatever tier the human's main
session happens to be on, which defeats the stated goal of this harness:
judgment-heavy roles (Product, Project, Architecture, Design, Process)
consistently get the more expensive model regardless of what the human
was using for casual conversation, and execution-heavy roles (Developer,
QA) consistently get the cheaper one. Pinning also makes cost behavior
predictable when this template is copied into a project and run
repeatedly by people who didn't design it.

## Open questions / known limitations

These weren't fully resolved in this build and are worth revisiting:

1. **No hard mechanical rework-cycle counter.** As noted above, the cap
   is enforced by instruction and cross-checking, not a mechanism Claude
   Code enforces on its own. A sufficiently confused agent invocation
   could in theory miscount. Mitigation in place: `STATUS.md`'s Event Log
   plus three independent counters (Developer, QA, Project Manager) that
   should agree. If this ever proves unreliable in practice, consider an
   external counter file with a stricter format (e.g. a single integer)
   that a hook could validate before allowing a rework-cycle write.

2. **Path-scoped tool restrictions don't exist.** There's no way in
   current Claude Code frontmatter to say "this agent's `Write` tool may
   only touch `.claude-dev-team/workspace/**`." Every restriction of that
   shape in this harness (QA shouldn't touch source, agents shouldn't
   touch `.git` directly, etc.) is enforced by system-prompt instruction,
   backed in the git-specific case by the `PreToolUse` hook and the
   `permissions.deny` rule, but not backed by anything comparably strong
   for "don't write outside the workspace directory" in general. If
   Claude Code ever adds path-scoped tool permissions, tighten this.

3. **The Process Advisor's authority is intentionally soft.** It has read
   access to everything and no gate, by design — but that also means
   nothing forces anyone to actually invoke it. It's opt-in. Whether that
   is the right trade-off (vs. e.g. requiring a process review before
   completion approval) is a genuine open question; the reasoning here
   was that a mandatory step nobody asked for gets treated as
   bureaucratic overhead and skipped in spirit even when run in form. If
   in practice teams using this template never invoke it, consider making
   it a recommended (not required) step in the completion gate checklist
   instead of leaving it fully optional.

4. **Estimate-overrun detection depends on the Developer accurately
   self-assessing remaining effort.** This is the one place the harness
   asks an agent to predict its own future output rather than report a
   fact — inherently softer than the rest of the "quality is structural"
   principle. No better mechanism was designed for this build; a
   time-based or turn-count-based proxy might be more mechanical but
   wasn't included here because turn count doesn't map cleanly to
   estimate units that vary by project (days, points, etc.).

5. **Verified against Claude Code's subagent docs as of mid-2026**
   (`https://code.claude.com/docs/en/sub-agents`), including the current
   frontmatter field list, the `model` field's accepted values, and the
   `PreToolUse` hook pattern used for `block-git-write.sh`. If you're
   installing this on a much older or newer Claude Code version, spot-check
   the frontmatter schema still matches before trusting it blindly —
   some fields referenced here (`hooks`, `skills`, `memory`) are
   relatively recent additions and may not exist on older releases.

6. **This harness doesn't validate task-slug consistency for you.** If an
   operator typos a task slug between invocations (e.g. `add-csv-export`
   vs `add-csv-exports`), agents will simply report the expected file
   missing rather than silently working in the wrong directory — but
   there's no automated check preventing the typo itself. Low risk, but
   worth knowing.
