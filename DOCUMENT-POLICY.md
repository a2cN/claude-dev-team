# Document Policy — what gets committed, what gets thrown away

This harness runs on documents. That is a deliberate choice (see
`CHANGELOG.md`, "Why file-based handoff"), but it comes with a failure
mode that has to be designed against rather than hoped away:

> **A document-driven process degrades into a document-maintenance
> process.** Every artifact that outlives its usefulness becomes a thing
> someone has to keep true, and the moment it stops being true it is worse
> than absent — because it still reads as authoritative.

Two independent field reports drove this policy, and they pull in
*opposite* directions:

- A post-mortem of a 13-unit AI-assisted build where the team's approved
  visual mock (2,323 lines of JSX, 66 screenshots) existed in the repo but
  was on **zero** of the 13 code-generation plans' reading lists. Three
  components were never built; the release shipped with no map. Lesson:
  **a document that isn't on a reading path does not exist.** Coverage is
  not the metric — *reachability* is.
- A practitioner write-up arguing that **implementation plans should not
  be version-controlled at all**, because every code change then obliges a
  second edit to the plan, and that double-bookkeeping cost is what
  actually kills the practice. Its counter-proposal: put the durable part
  in the PR body and the commit history, and let the transient part expire.

Both are right about different documents. The axis that separates them is
not importance — it's **whether the document's value survives the merge**.

## The classification

The naive split is two-way — keep it or bin it — and it is wrong. The
write-up's objection to version-controlling a plan is specifically about
**maintenance cost**: every code change obliges a second edit to keep the
plan true. That objection only applies to a document living in the working
tree with a standing obligation to be currently correct.

**An immutable archive has no maintenance cost.** Nobody updates it because
updating it is forbidden. It is a dated snapshot, understood to be stale,
and "what we believed on 2026-07-17" is exactly what a retrospective needs.
So there are three fates, not two:

| Fate | Obligation to be currently true | Git | Lives in |
|---|---|---|---|
| **Living** — decision & rationale | **yes** | commit | `docs/adr/`, `docs/design/` |
| **Archive** — immutable snapshot of what the inputs were | **none — updating is forbidden** | commit | `docs/archive/<date>-<slug>/` |
| **Evidence** — proof of verification | none | commit (as history) | PR body / commit message |

Nothing is deleted. What changes is the *obligation* attached to it:

- **Living** artifacts must be kept true, and must be placed where an agent
  will actually read them (see "Reachability" below). `30_architecture.md`,
  `40_design_brief.md` and `45_design_approval.md` are promoted here,
  because *why not the alternative* is never derivable from code.
- **Archive** artifacts are copied once, at completion, and never touched
  again. Their value is not as instruction — that expired at merge — but as
  **the record of what the inputs were**, which never expires. See
  "Retrospective readiness" below; this is the class the first draft of this
  policy got wrong.
- **Evidence** goes in the **PR body / commit message**, not a tracked
  file. This satisfies both sources at once: the post-mortem needs a third
  party to be able to verify a completion claim months later; the
  write-up needs it to not become a file anyone maintains. Git history is
  append-only by construction and is exactly the right substrate for it.

The danger the write-up warns about — a stale plan still reading as
authoritative — is real, and is prevented by **location and label**, not by
deletion. `docs/archive/` is deliberately **off** every implementation
reading path and **on** the retrospective reading path only. An agent
implementing a feature must never treat it as a source of truth; that is
stated in `CLAUDE.md` and is the whole reason the archive is a separate
directory rather than a stale file in `docs/`.

## Per-artifact ruling

| Artifact | Fate | Where its value ends up |
|---|---|---|
| `00_request.md` | archive | `docs/archive/`; one-line背景 in the PR body |
| `10_product_brief.md` | archive | `docs/archive/`; goal statement in the PR body |
| `20_project_plan.md` | archive | `docs/archive/` — **the record of what was scoped and approved** |
| `STATUS.md` | archive | `docs/archive/` — the Event Log is the timeline of the run |
| `30_architecture.md` | **living** + archive | promoted to `docs/adr/NNN-<slug>.md` |
| `40_design_brief.md` | **living** + archive | promoted to `docs/design/<slug>/brief.md`, **screenshots included** |
| `44_mock_build.md` | archive | `docs/archive/` — the record of what was rendered for the human to look at |
| `45_design_approval.md` | **living** + archive | promoted to `docs/design/<slug>/README.md` — **at its own gate, not at completion** |
| `50_implementation.md` | archive | `docs/archive/` — **the record of what the implementer actually read** |
| `60_qa_report.md` | archive + evidence | `docs/archive/`; evidence block in the PR body |
| `70_process_review.md` | archive | `docs/archive/`; lessons filed back into this harness repo's `CHANGELOG.md` |
| `90_completion.md` | archive + evidence | `docs/archive/`; **pasted verbatim into the PR body** |

The three `living` rows are promoted *and* archived — the promoted copy is
rewritten for a stranger six months out and is maintained; the archived copy
is the verbatim original and is not. They diverge on purpose.

One artifact is not in this table because it does not belong to a run:
`docs/OPEN-DECISIONS.md` is a **project-level living ledger**, created once
and never archived, because the questions it holds routinely outlive the unit
that raised them. See "One ledger for open decisions" below.

Everything else is archived verbatim and never edited again. Concretely, at
completion the whole workspace is copied to
`docs/archive/<YYYY-MM-DD>-<task-slug>/` in one move, which is why the
per-file rows above mostly say the same thing: **the default is archive, and
the interesting decisions are which two files also become living documents
and which sections also become PR evidence.**

The consuming project's `.gitignore` still gets one line — the *workspace*
is not the archive, and in-flight state has no business in a commit:

```gitignore
# Claude Dev Team pipeline workspace — transient by policy.
# Durable artifacts are promoted out of here (docs/adr/, docs/design/);
# evidence goes into the PR body. See DOCUMENT-POLICY.md.
.claude-dev-team/workspace/
```

Ignoring the whole workspace, rather than listing individual files, is the
point: **nothing in the workspace is committed by default, and the two
artifacts that must persist leave it by an explicit act.** The inverse
setup — a tracked directory with per-file exclusions — makes persistence
the accident and forgetting the default.

### Trade-off this accepts

A gitignored workspace is not shareable via the repo. On a solo or
single-machine project that costs nothing. On a team, in-flight state has
to be shared some other way (or the ignore relaxed to
`!30_*`/`!40_*`/`!45_*` and the promotion step dropped). Decide this once,
per project, and record the decision — don't let it drift.

It also means CI cannot see a run that is in flight, which is why
`scripts/verify-dev-team.sh` asks the PR to declare which runs it carries
rather than discovering them. That declaration is a self-report and is worth
being honest about: it cannot catch a pipeline run that left no trace at
all. What it does catch is the case that actually happened — a run that
produced artifacts and then dropped them — and it converts an omission from
silence into a line a reviewer can see.

## Promotion (the "graduation" step)

Promotion is a stage of the pipeline, not a chore. **An artifact is promoted
at the gate that approves it** — which for most artifacts is the completion
gate, and for `45_design_approval.md` is its own gate, because a design canon
that arrives after the implementation is not a canon.

1. The Project Manager, drafting `90_completion.md`, lists exactly which
   artifacts are due for promotion and their destination paths.
2. The Developer (who has `Write`) copies them, trimming the
   pipeline-scaffolding sections (task slug, estimate, approval fields)
   and keeping the decisions and their rationale.
3. Promoted files are part of the change, appear in the diff, and are
   reviewed by the human at the completion gate like any other file.

Why copy rather than move-and-symlink or just commit in place: the
workspace copy keeps its audit context (revision history, what QA said);
the promoted copy is written for a reader six months out who has never
heard of this task slug. They are genuinely different documents.

### The order is part of the rule

Archiving is simpler than promotion — one verbatim copy of the whole
workspace to `docs/archive/<YYYY-MM-DD>-<task-slug>/`, no trimming, no
rewriting, and no subsequent edits ever — but it must happen **last**, and
specifically **after the human has signed the completion gate**:

1. The Project Manager drafts `90_completion.md`, promotion rows `pending`.
2. **The human signs it**, in the workspace copy, having looked at the
   evidence and the diff.
3. The Developer promotes, flipping each promotion row to `done`.
4. The Developer archives the workspace, verbatim, and stops.

An earlier version of this policy left that order to be inferred, and on its
first real run the workspace was archived before the human signed. The
signature then had nowhere to go that was not an edit to an immutable
snapshot. The archive's whole value is that a reader six months out can trust
that nothing in it moved after the date on the directory, and that guarantee
degrades silently — an edited archive looks exactly like an unedited one.
Stated as the invariant, because it is checkable:

> **No archived file may contain a field that anyone is expected to fill in
> later.** If a document has a blank a human is meant to write in, it is not
> ready to be archived, and archiving it is the bug — not the blank.

The Developer therefore treats `90_completion.md`'s `Approval Status` as a
hard gate on promoting and archiving at all, exactly as it already treats
`20_project_plan.md`'s field as a hard gate on implementing.

One row escapes this, unavoidably: the Developer cannot mark the *archive*
row `done` inside a copy that the act of marking would have to precede. So
the archive row is left `pending` by design, and its truth is established by
the archive directory existing — not by anything written inside it. Every
other row must read `done` or `N/A`.

If archiving is skipped entirely, gitignoring the workspace destroys the
run's inputs at merge. See the next section for why that matters more than
it sounds like it does.

## Retrospective readiness

**This is the section the first draft of this policy was missing, and its
absence was a genuine defect.** A reviewer asked whether an AI-run
retrospective of the kind that motivated this harness could be reconstructed
from the living documents plus the PR bodies. The answer was no, and the
proof is the post-mortem's own reproduction steps:

| What the retrospective proved | The file it needed |
|---|---|
| **Thirteen implementation plans referenced the approved mock zero times** — the finding that explained three unbuilt components | the implementation plans |
| The implementer had itself written "visual confirmation in a browser is required" while no such step existed in the process | the implementation notes |
| The acceptance criteria for the relevant unit omitted the missing component | the unit-of-work / plan document |
| The state file recorded "all units complete" at a moment when it was collectively false | the status file |
| Which components remain unimplemented; the size of the rework | the code and `git diff` — **these survive regardless** |

Four of the five load-bearing findings needed documents the two-way split
discarded. Stated as the principle:

> **A diff records the output. Nothing records the input unless you keep
> it.** And the post-mortem's central finding was *"what is not in the input
> is not in the output."* Discard the inputs and you discard the route to
> that finding — you are left able to see only that something is missing,
> never why.

So: archive the whole workspace, and make the input record explicit rather
than incidental.

### Declared inputs

The post-mortem could only answer "did the implementer ever see the design?"
by grepping thirteen files for a path string that happened to appear — or in
that case, happened not to. That worked, but it worked by luck: a plan could
have referenced the mock in prose without the path, or referenced the path
without reading it.

Every artifact-producing role in this harness therefore writes an **`## Inputs
Read`** block listing, as literal repo-relative paths, the files it actually
opened — *not* the files it was told to open, and explicitly noting anything
it was expected to read and didn't. `agents/solution-architect.md`,
`agents/developer.md`, and `agents/quality-assurance.md` all carry it; QA's
doubles as a cross-check against the Developer's, and a Developer that never
opened a design artifact the task depended on is a finding QA must report
whether or not the code happens to work.

That converts the single most expensive query in the post-mortem into a
one-liner across the archive:

```bash
# Did any run's implementer ever read the design SSOT?
grep -rn "docs/design/" docs/archive/*/50_implementation.md
```

This is the one place this harness is designed to be *better* than the
process it learned from, rather than merely to avoid repeating it.

### What the archive is not

The archive is **not** a source of truth for implementation, and no agent
may treat it as one. It is a record of what was believed at a date, kept
precisely because it will become wrong. Its reachability is deliberately
one-sided:

- **On** the retrospective reading path.
- **Off** every implementation reading path. `CLAUDE.md` must say so.

That asymmetry is what makes keeping stale documents safe. The failure the
write-up warns about is a stale plan read as current; the failure the
post-mortem documented is an approved artifact never read at all. Location
and labelling resolve both at once — which is why the archive is a separate
directory rather than an old file left lying in `docs/`.

## Reachability beats coverage

A promoted document that no agent reads is the exact failure the
post-mortem documented. Promotion is therefore only half the rule — the
other half is that promoted documents must be **on a reading path**:

- The consuming project's root `CLAUDE.md` must name `docs/adr/` and
  `docs/design/` explicitly, as paths, not as a genre ("see our design
  docs" is not reachable).
- Any agent whose stage depends on a prior decision reads the relevant
  promoted file by path, not by search.
- **`docs/design/` outranks prose.** Where a screenshot or mock and a
  written spec disagree, the visual artifact is correct and the prose is
  the stale one. State this in `CLAUDE.md`; do not leave it to be inferred.
- **Inside `docs/design/<slug>/`, `README.md` outranks `brief.md`.** The
  README is the promoted `45_design_approval.md`: the values a human
  actually chose. The brief is the promoted `40_design_brief.md`: what was
  proposed, including options that were not taken. A brief is written
  entirely in proposal voice, so promoting one as canon publishes a canon
  that says its own values are unconfirmed and lists the rejected
  alternatives as though they were live. Keeping both is deliberate — the
  rationale is worth reading — but only one of them is the answer.

And the rule that turns a gap into a stop rather than an invention:

> **An unspecified requirement is an incomplete ticket, not a licence to
> decide.** If an artifact an agent needs is absent, silent, or
> self-contradictory, that is an upstream defect to be flagged — never a
> blank to be filled with a plausible guess.

This is the single highest-leverage line in this document. In the
post-mortem, every one of the never-built components sat behind a gap that
some agent quietly filled with something reasonable, and reasonable is
indistinguishable from correct until someone looks at the screen.

## Push the spec toward the code

The write-up's strongest idea, and the cheapest defence against
double-bookkeeping: **the closer a spec lives to the code it constrains,
the less likely it is to rot, and the more likely an agent is to read it.**
A block comment above a function is on the reading path by construction —
nobody has to remember to include it.

```ts
/**
 * 【Result view】Reads the generated English aloud.
 * - Initial implementation: Web Speech API (SpeechSynthesis).
 * - Cloud TTS must remain a drop-in swap — call only through this
 *   interface, never `speechSynthesis` directly from a component.
 * - Ubiquitous language: "read aloud" covers the generated English only;
 *   the Japanese translation is never spoken.
 */
```

Corollary, also from the write-up: **domain vocabulary is the strongest
search key an agent has.** If the same concept is called `deck` in one file
and `collection` in another, agentic search silently misses half the
codebase. Fix the vocabulary once, in `CLAUDE.md`, and use it verbatim in
identifiers *and* in comments.

So: a written spec document is best understood not as the answer, but as
**an index into the code** — the thing that tells an agent where to look.
Judge it on whether it gets the reader to the right place, not on whether
it describes everything.

## Prefer mechanical enforcement to prose

> "Writing 'please don't do it this way' in the rules does not mean an LLM
> will honour it 100% of the time."

Every prose constraint is a probabilistic control. For each rule in a
project's `CLAUDE.md`, ask: **can this be checked by a machine?** If yes,
the prose is documentation and the check is the control. If no, accept
that it will occasionally be violated and put a verification step
downstream of it.

| Rule | Mechanical form |
|---|---|
| Don't use `window.alert` | ESLint `no-alert` / `no-restricted-globals` |
| Server-only secret must not reach the client | ESLint restricting `process.env.<KEY>` outside the server directory |
| Mocks must never be the silent default | env validation that **fails the build** on an unset/invalid provider |
| Minimum touch-target size | assertion on computed size in an E2E test |
| No agent runs git writes | `permissions.deny` + the `PreToolUse` hook |
| Promotion and archiving actually ran | `scripts/verify-dev-team.sh`, in CI on every PR |
| Nothing archived carries an unsigned field | the same script greps `docs/archive/` for `PENDING_HUMAN_APPROVAL` |
| An archived file is never edited | the same script asserts `git diff --name-status` shows only `A` under `docs/archive/` |
| Every open question has one home | the same script resolves every cited `OD-` id against the ledger |

A rule with a mechanical form and no mechanism is a rule you have decided
to violate later.

The first four rows of this table were mechanised long before the last
four, and the gap was not an oversight so much as a blind spot: it is
easier to see that a rule about *code* wants a linter than to see that a
rule about *the process itself* wants one too. The promotion step had a
precise checkable form — "does this PR contain an archive directory for
every run it claims" — and relied entirely on someone remembering. On the
first run where nobody did, the entire audit trail for the change was
discarded at merge, and the only reason anyone noticed was that a reviewer
happened to click a link into a gitignored path.

## Update discipline: append, or derive

The post-mortem's most transferable finding concerns *how* files are
updated, independent of what they contain:

- The file updated by **appending** stayed trustworthy for three months.
- The files updated by **overwriting** rows and checkboxes went wrong
  silently — in a **single-person** project, with zero concurrent writers.
  "All 13 units complete" was written truthfully, field by field, and was
  collectively false.

Overwriting loses the previous value, so a wrong write leaves no trace and
reads exactly like a right one. Hence:

1. **Append-only wherever a log will do.** `STATUS.md`'s Event Log is the
   authority; see `templates/STATUS.md`.
2. **Derive summaries; don't maintain them.** "Rework cycles used" should
   be *counted from* the Event Log at read time, not stored as a field
   that someone remembers to increment.
3. **If it must be a stored mutable field, make it cheap to falsify.** Say
   which lines it was derived from, so a reader can check it in seconds.

Stated as a principle:

> **Designing for an AI that keeps documents correctly updated does not
> scale. Moving toward state that is correct without being updated is the
> only thing that does.**

## One ledger for open decisions

The principle above has a direct casualty, and it took a real run to find
it. A human at a completion gate asked the plainest possible question —
*what is still undecided?* — and answering it required reading five
artifacts, each listing open items under a different heading, in a different
framing, with a different count:

| Artifact | Its heading for open items | Items listed |
|---|---|---|
| `90_completion.md` | Outstanding follow-ups | 3 |
| `60_qa_report.md` | Unverifiable Requirements | 3 |
| `40_design_brief.md` | Open Questions for the Human | 3 |
| `STATUS.md` | Open escalations | 3 |
| the promoted ADR | what the approval gate would settle | 3 |

The union was **six**. The document whose entire purpose is to hand the unit
to the human listed three of them, and the two it silently dropped were live
design values that would have shipped as whatever the implementer happened
to choose. Nothing had gone wrong at any single step. There were simply five
prose lists and no step that reconciled them, which is exactly the class of
failure the append-or-derive rule exists to prevent — five stored mutable
summaries of the same underlying state.

So: **`docs/OPEN-DECISIONS.md`, one table, one row per open question, and no
artifact keeps its own list.** Every role appends rows; artifacts *cite ids*
where they used to restate items. Ids are `OD-<task-slug>-NN`, scoped to the
slug so an agent allocating one greps only its own rows and two live
workspaces cannot collide.

Three properties make it work, and dropping any one of them puts the five
lists back:

- **Only a human writes `CLOSED`.** Same rule shape, and same reasoning, as
  `Approval Status: APPROVED`. Agents may append rows and append context to
  existing ones; they may never close one, and never delete one.
- **The ledger is not archived, and does not belong to a run.** It lives in
  `docs/`, on the implementation reading path. This is the whole point: a
  note saying "these requirements are unverifiable, someone must own them
  next cycle" is worthless if it is filed in the one directory the next
  cycle is told not to read. Rows outliving their unit simply stay `OPEN`
  after the workspace is archived — there is no migration step to forget.
- **It does not compete with `STATUS.md`.** The Event Log stays the
  authority for *what happened when*, append-only, and every escalation
  entry cites its `OD-` id. The ledger is the authority for *what is still
  open*. Two authorities over one fact would be the same bug again; two
  authorities over two different facts, joined by an id, is a foreign key.

The count that used to disagree is now `grep -c`.

## Approve artifacts, not reports

The post-mortem's approval gates were all *plan-approval* gates. There was
no gate at which a human examined a working artifact. So when a pull
request said "412 tests green, CI passing," a reviewer had no means to
disagree, and approval collapsed into acknowledging a green checkmark.

This harness had the same shape: at the time, both of its gates read a
document.

It now has three gates, and the middle one exists entirely because of this
section. At the **design-approval gate** the human is not asked to agree
with a description of a layout — they are asked to look at something that
was rendered, and to choose. Prose cannot be the artifact there: the
Designer has no browser and no Bash and cannot produce a screenshot, so a
design brief is a proposal no matter how much detail it carries. Something
has to be built and looked at before any visual requirement is verifiable at
all, which is why `44_mock_build.md` exists and why the canon that the gate
produces is a *different document* from the brief that proposed it.

Therefore the **completion gate requires evidence, not prose**. See
`agents/project-manager.md` — `90_completion.md` carries an Evidence block,
and the gate instruction to the human is to look at the evidence, not to
read the summary. What counts as evidence:

- a screenshot of the actual running feature (not of the test output);
- a URL to a deployed or locally-running instance, holding real data;
- an end-to-end test log showing a full user path;
- verbatim quality-gate output, pasted, not characterised.

Corollary on where review effort belongs: "was this built the way the plan
said" is a conformance question, mechanisable and delegable to
self-review. **Human review should be spent on the question a machine
cannot answer — is this the right thing — and that question requires
something to look at.**

## Applying this to a new project — checklist

- [ ] `.claude-dev-team/workspace/` in `.gitignore`
- [ ] `docs/adr/` and `docs/design/` exist and are named, as paths, in `CLAUDE.md`
- [ ] `docs/archive/` exists, and `CLAUDE.md` states it is **off** the
      implementation reading path and immutable once written
- [ ] `docs/OPEN-DECISIONS.md` exists, is named as a path in `CLAUDE.md`, and
      `CLAUDE.md` states that only a human may close a row
- [ ] `CLAUDE.md` states that visual artifacts outrank prose on conflict, and
      that `docs/design/<slug>/README.md` outranks `brief.md`
- [ ] `CLAUDE.md` states the "unspecified means incomplete ticket" rule
- [ ] `CLAUDE.md` fixes the project's ubiquitous language
- [ ] Every mechanisable rule in `CLAUDE.md` has its mechanism wired up
- [ ] `scripts/verify-dev-team.sh` is installed and runs in CI on every PR
- [ ] The completion gate's evidence requirement is understood before the first run
- [ ] The order is understood: **sign, then promote, then archive** — never
      the other way round
