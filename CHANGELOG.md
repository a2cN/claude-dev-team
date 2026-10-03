# Design Notes / Changelog

## v1.2.0 — the gaps a real run found

Everything below was reported by one run of the pipeline against a real
consuming project. Four separate issues, and they turned out to share a
root: **the boundaries between approving, confirming and archiving were
never defined on the time axis.** The documents said what each step
produced; nothing said what order the steps happened in, so the order
varied, and each of the four failures is a different consequence of that.

### Promotion and archiving now have a mechanism

QA returned PASS, a PR was opened, and the promotion/archive step never
ran. Nothing caught it. The change would have merged with the whole audit
trail — plan, QA report, implementation notes, design brief — destroyed by
the gitignore. It surfaced only because a reviewer clicked a link into a
gitignored path and asked why.

`DOCUMENT-POLICY.md` had already stated the diagnosis, one section away
from the defect: *"A rule with a mechanical form and no mechanism is a rule
you have decided to violate later."* The promotion step had a precise
checkable form and relied on someone remembering. It was not on the
"Prefer mechanical enforcement to prose" table; the first four rows of that
table were all rules about *code*, which is the blind spot — it is easier
to see that a rule about code wants a linter than to see that a rule about
the process wants one too.

So `scripts/verify-dev-team.sh` now exists, with a fixture suite
(`scripts/test/run-tests.sh`) and a sample workflow. It checks that every
declared run was archived, that every promotion row is `done`, that
nothing archived is waiting for a signature, that every cited ledger id
resolves, and — for the first time — that `docs/archive/` is genuinely
append-only, by asserting the diff against it contains only additions.

The honest limit is documented rather than glossed: because the workspace
is gitignored, CI cannot see a run in flight, so the PR declares its runs
with a `Dev-Team-Run:` line. That is a self-report and cannot catch a run
that left no trace at all. It catches the failure that actually happened —
artifacts produced and then dropped — and turns an omission from silence
into a reviewable line.

### The completion signature no longer arrives after the archive

`90_completion.md` ends with the human's approval field. The workspace was
archived at completion, as the policy requires, and *then* the human
approved — so the only copy of the field lived inside an immutable
snapshot. The approval step and the archive rule were mutually exclusive as
written: either the human edits a frozen archive, or the approval is never
recorded anywhere.

The fix is ordering, not a new document. `PIPELINE.md` step 8 is split into
**sign (9) → promote and archive (10) → git (11)**, the Developer now
carries a hard gate refusing to promote or archive until
`90_completion.md` reads `APPROVED`, and `DOCUMENT-POLICY.md` states the
invariant that makes it checkable:

> **No archived file may contain a field that anyone is expected to fill in
> later.**

One consequence had to be designed around rather than fixed: the Developer
cannot mark the *archive* row `done` inside the copy that marking would
have to precede. That row stays `pending` by design and its truth is the
directory existing, which is why check `B1` exempts it.

### One ledger for open decisions

A human at the completion gate asked *"what is still undecided?"* Answering
it needed five artifacts, each listing open items under a different
heading, each saying three. The union was **six**. `90_completion.md` — the
document whose entire job is to hand the unit to the human — listed three,
and the two it dropped were live design values that would have shipped as
whatever the implementer happened to pick.

Nothing had gone wrong at any single step. There were five prose lists and
no step that reconciled them, which is the failure `DOCUMENT-POLICY.md`'s
own append-or-derive rule already predicts: five stored mutable summaries
of one underlying state.

`docs/OPEN-DECISIONS.md` is now the single place a row is created, ids are
`OD-<task-slug>-NN`, and artifacts cite ids instead of restating items. The
count that used to disagree is `grep -c`. Only a human writes `CLOSED` —
same rule shape as `APPROVED`, same reasoning. The ledger is not archived
and does not belong to a run, which is the point: rows that outlive their
unit simply stay `OPEN`, so there is no migration step to forget. A related
contradiction is fixed at the same time — `templates/STATUS.md` claimed to
be transient and uncommitted while the per-artifact table archived it,
which is how escalations were dying at archive time.

### A design brief can no longer be promoted as canon

`docs/design/` is the highest-ranked canon in a consuming project, and
promotion into it was specified as a copy of `40_design_brief.md`. That
cannot be done honestly, because a brief is written entirely in proposal
voice: candidates, a recommendation ranking, an open-questions section. A
verbatim promotion publishes a canon that opens by stating its own values
are unconfirmed and lists the rejected options as though they were live.

Concretely: the Designer's ranking was C→B→A and the human chose A. A
verbatim promotion leaves "recommended: C→B→A" sitting in canon beside an
implementation using A, where the next agent has every reason to "fix" the
discrepancy in the wrong direction.

So the approved values are now a **different document**, exactly as this
policy already argued for archive-vs-promoted: `45_design_approval.md`,
drafted by the Designer with the answers blank, filled in and signed by a
human at a third gate, and promoted to `docs/design/<slug>/README.md`
(which outranks the promoted `brief.md`). It carries the four sections that
had to be invented by hand on the run: confirmed value, rejected proposal
marked dead, who decided and when, and **what this canon does NOT cover** —
without which a populated `docs/design/` silently implies full coverage,
which is the original failure re-run with a full directory instead of an
empty one.

The gate sits **before** implementation, not at completion, and promotes
immediately. v1.1.2 already required an approved visual artifact before UI
implementation but gave the approval nowhere to be recorded; this closes
that. The mock the human looks at gets its own slot, `44_mock_build.md`,
rather than reusing `50_implementation.md` — which is revised in place, so
the feature build would overwrite the record of what was shown, and whose
revisions the QA rework cap counts.

The ceremony cost is real and is recorded as a known limitation. The
mitigation is the cheap path when canon already exists: a one-row sheet
confirming it still governs, no mock round. That path has to stay a
*positive statement* in `20_project_plan.md` — the Developer treats a
missing approval sheet as a hard stop and may only proceed without one by
quoting the plan's line saying the gate was not required. The moment "no
visual surface" becomes something an agent infers rather than something a
human wrote down, the gate is dead.

### Incidental corrections

- `PIPELINE.md` claimed "there is no `70` in the main line" while
  `70_process_review.md` occupied it. The genuinely free slots are `80`
  and the intra-decade gaps; `44` and `45` were inserted into the latter.
- `agents/developer.md` contained no mention of promotion or archiving,
  despite being the assignee. The instruction existed only inside an HTML
  comment in `agents/project-manager.md`'s output template — a file the
  Developer never reads. It now has a section of its own.
- `PIPELINE.md` depended on `STATUS.md` as a source of truth in two places
  without ever describing it. It now has a section.

## v1.1.1 — retrospective readiness (fixes a real defect in v1.1.0)

v1.1.0's document policy was a **two-way** split: keep it or bin it. A
reviewer asked the obvious question — could an AI-run retrospective, of the
kind that motivated this whole harness, be reconstructed from the living
documents plus the PR bodies alone? The answer was **no**, and the proof is
the source post-mortem's own reproduction steps. Four of its five
load-bearing findings needed files v1.1.0 threw away:

| Finding | File it needed | v1.1.0 fate |
|---|---|---|
| Thirteen implementation plans referenced the approved mock **zero times** — the finding that explained three unbuilt components | the plans | discarded |
| The implementer had itself written "visual confirmation in a browser is required" while no such step existed | the implementation notes | discarded |
| Acceptance criteria for the relevant unit omitted the missing component | the plan | discarded |
| The state file said "all units complete" when that was collectively false | the status file | discarded |

Stated as the principle now in `DOCUMENT-POLICY.md`:

> **A diff records the output. Nothing records the input unless you keep
> it.** And the post-mortem's central finding was *"what is not in the input
> is not in the output."* Discard the inputs and you discard the route to
> that finding — you can see only that something is missing, never why.

### Three fates, not two

The error was treating "not maintained" as equivalent to "not kept." The
write-up's objection to version-controlling a plan is about **maintenance
cost** — every code change obliging a second edit — and that only applies to
a document with a standing obligation to be *currently* true. **An immutable
archive has no maintenance cost, because updating it is forbidden.** "What we
believed on 2026-07-17" is exactly what a retrospective needs, and it being
stale is the point rather than the problem.

So: **living** (must stay true → `docs/adr/`, `docs/design/`), **archive**
(immutable snapshot, updating forbidden → `docs/archive/<date>-<slug>/`), and
**evidence** (PR body). Nothing is deleted; what varies is the obligation
attached to it. At completion the whole workspace is copied verbatim to the
archive, in addition to the two promotions.

The hazard the write-up warns about — a stale plan still reading as
authoritative — is handled by **location and label**, not deletion:
`docs/archive/` is deliberately **on** the retrospective reading path and
**off** every implementation reading path. That asymmetry is what makes
keeping stale documents safe, and it resolves both failure modes at once: the
write-up's (stale doc read as current) and the post-mortem's (approved
artifact never read at all).

### Declared inputs — the one place this harness improves on its source

The post-mortem could only establish "the plans never referenced the mock" by
grepping thirteen files for a path string that happened not to appear. That
worked by luck; a plan could have cited the mock in prose without the path,
or the path without reading it.

`agents/solution-architect.md`, `agents/developer.md`, and
`agents/quality-assurance.md` now each write an **`## Inputs Read`** block
listing, as literal repo-relative paths, the files they *actually opened* —
not the files they were told to open, and explicitly flagging anything they
were expected to read and didn't. QA's block doubles as a cross-check on the
Developer's: a Developer that never opened a design artifact the task
depended on is a finding QA must report whether or not the code works.

The most expensive query in the post-mortem becomes:

```bash
grep -rn "docs/design/" docs/archive/*/50_implementation.md
```

An artifact never reveals what its author didn't see. This is the only
mechanism in the harness that recovers that.

Also updated: `agents/project-manager.md` (`90_completion.md`'s promotion
table gained an archive row, with the reason stated so it isn't skipped on a
smooth run), `PIPELINE.md` step 8, and the consuming-project checklist.

## v1.1.0 — document policy, append-only status, evidence-based completion

Driven by two outside inputs that pulled in opposite directions: a
post-mortem of a 13-unit AI-assisted build that shipped with three
components never implemented, and a practitioner write-up arguing that
implementation plans should not be version-controlled at all. Both were
right about different documents; `DOCUMENT-POLICY.md` is the new file that
resolves them. Summary of what changed and why:

### `DOCUMENT-POLICY.md` (new) — which documents are committed, and which are thrown away

v1.0.0 was silent on this, which in practice means "commit everything" —
and a document-driven process that commits everything degrades into a
document-maintenance process. The policy classifies each artifact by
**whether its value survives the merge**, not by how important it feels:

- **Transient** (`00`, `10`, `20`, `50`, `STATUS.md`): not committed. After
  the merge the diff is the authoritative record, and a plan describing an
  earlier intention is a liability, because it still reads as
  authoritative.
- **Durable** (`30_architecture.md`, `40_design_brief.md`): committed —
  *why not the alternative* is never derivable from code. Promoted out of
  the workspace into `docs/adr/` and `docs/design/`.
- **Evidence** (`60`, `90`): into the PR body. Git history is append-only
  by construction, which is exactly the substrate this needs, and it avoids
  creating one more tracked file someone has to keep true.

The consuming project gitignores the *whole* workspace rather than
excluding files inside a tracked directory. That inversion is the point:
nothing persists by default, and the two artifacts that must persist leave
by an explicit act. The reverse arrangement makes persistence the accident
and forgetting the default.

Also documented there: reachability over coverage (the post-mortem's
approved mock was 2,323 lines and 66 screenshots, and was on zero of 13
reading lists — coverage was total, reachability was nil); the rule that an
unspecified requirement is an incomplete ticket rather than a licence to
decide; pushing spec into DocComments so it is on a reading path by
construction; ubiquitous language as the load-bearing input to agentic
search; and preferring a mechanism to a prose rule wherever one exists.

### `templates/STATUS.md` — rewritten append-only, with derived summaries

This is the change with the strongest evidence behind it. In the
post-mortem, the file updated by *appending* stayed trustworthy for three
months; the files updated by *overwriting* rows and checkboxes went wrong
silently — in a single-person project with zero concurrent writers. "All 13
units complete" was written truthfully field by field and was collectively
false.

v1.0.0's `STATUS.md` had exactly that shape: mutable summary fields at the
top ("Current stage", "Rework cycles used: 0 / 2", a human-gate table whose
rows were rewritten in place) that only the Project Manager overwrote. An
overwrite destroys the prior value, so a wrong write leaves no trace and is
indistinguishable from a right one.

Now: the Event Log is append-only and authoritative, nobody edits an
existing entry (corrections are appended), and every summary field is
recomputed from the log with a citation of the entries it came from. Rework
cycles are *counted from* the log rather than stored as an incremented
counter. `agents/project-manager.md` was updated to match.

The generalisable form: **designing for an AI that keeps documents
correctly updated does not scale; moving toward state that is correct
without being updated is the only thing that does.**

### Completion gate is now evidence-based, not report-based

v1.0.0 had two human gates and both of them read a document. That is the
same structure the post-mortem identified as its approval failure: all its
gates were plan-approval gates, none was an artifact-verification gate, so
when a PR said "412 tests green, CI passing," the reviewer had no means to
disagree and approval collapsed into acknowledging a green checkmark.

`90_completion.md` now carries an Evidence block — a screenshot of the
running feature (explicitly not of test output), a reachable instance
holding real data, an end-to-end run, verbatim quality-gate output — and
unfillable rows must be marked MISSING rather than omitted or substituted.
`PIPELINE.md` step 8 now tells the human to open the evidence *before*
reading the prose. The Project Manager's quality bar states that a
completion summary with a hand-waved Evidence block is not a completion
summary.

The division of review labour, borrowed from the write-up: "was it built
the way the plan said" is a conformance question, mechanisable and fit for
self-review. Human review should be spent on the question no machine can
answer — is this the right thing — and that question needs something to
look at.

### Promotion is now a pipeline step

`90_completion.md` gained an "Artifacts due for promotion" table, and
`PIPELINE.md` step 8 checks it. Without this, gitignoring the workspace
would silently discard every architectural decision at merge — trading one
failure mode for another. Promotion copies rather than moves: the workspace
copy keeps its audit context, the promoted copy is written for a reader six
months out who never heard of the task slug. They are different documents.

### The "incomplete ticket" rule, propagated to every role that can hit a gap

`agents/developer.md` already handled this well in v1.0.0 ("that's a gap in
an upstream artifact, not something to quietly work around in code"). It is
now also an explicit escalation trigger in
`agents/solution-architect.md` — including the case of a design artifact
expected at a stated path and not found, which is a gap and not an
invitation to specify the UI yourself — and in
`agents/quality-assurance.md`, in the form the role actually meets it:

> A requirement nobody can check is silently reclassified as
> not-a-requirement, and then it never gets built.

So `60_qa_report.md` now has UNVERIFIABLE as a first-class result alongside
PASS and FAIL, plus a dedicated Unverifiable Requirements section, and QA's
quality bar requires the criteria set in the report to match the criteria
set in the brief — a reader must not have to diff two files to notice
something went missing. QA is explicitly forbidden from resolving these in
either direction: not passing them on the assumption they're probably fine,
not rejecting them on its own aesthetic judgment.

### Still open after this revision

- The Designer stage now has a durable destination (`docs/design/`), and QA
  will now surface unverifiable visual requirements rather than swallow
  them — but nothing in the harness *requires* a visual artifact to exist
  before UI work begins. A project whose design direction is undecided can
  still reach implementation with no visual correct-answer, which is a
  strictly worse position than the post-mortem's (it at least had an
  approved mock, merely unreachable). Currently mitigated by instruction in
  the consuming project's `CLAUDE.md` and by detection at the QA stage,
  which is late. The structurally correct fix is a gate before UI
  implementation, which would mean a new pipeline stage; deferred rather
  than rushed.
- `70_process_review.md` is classified transient, with its lessons "filed
  back into this harness repo's `CHANGELOG.md`" — but that filing is a
  manual act by the human with no step in `PIPELINE.md` prompting it. The
  cross-project learning loop is therefore the least structural part of
  this design, which is ironic given that this whole revision came out of
  exactly such a loop.

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

7. **`block-git-write.sh` runs in degraded mode without `jq`.** The hook
   prefers `jq` to extract `.tool_input.command` precisely. When `jq` is
   absent it flattens the raw JSON payload and applies the same patterns to
   the whole thing, which over-blocks rather than under-blocks (a read-only
   command whose *description* mentions "commit" can be flagged). Install
   `jq` for precise matching. The block message says which mode it ran in.

## Post-build fix (applied after the initial commit)

**`block-git-write.sh` failed open when `jq` was missing — fixed.**

The initial version exited `0` (allow) if `jq` was not on `PATH`. Because
`jq` is not installed by default on many systems — including the machine this
harness was developed on — the hook silently allowed *every* git-mutating
command it was written to block. The regex patterns themselves were correct
(verified 13/13 against the intended allow/block cases); the defect was
entirely in the plumbing ahead of them, which is why isolated pattern testing
during the build did not catch it. End-to-end testing through the real hook
entry point, on a machine without `jq`, is what surfaced it.

The fix removes the hard `jq` dependency and makes the check fail *closed*:
`jq` is used when present, and a payload-flattening fallback runs when it is
not. Re-verified 13/13 end-to-end with `jq` absent.

Generalizable lesson for this harness: a control that fails open is worse than
no control, because it reads as protection while providing none. Any future
hook added here should be tested through its real entry point in the
environment it will actually run in, not just as isolated logic — and should
prefer over-blocking to under-blocking when its inputs are unavailable.
