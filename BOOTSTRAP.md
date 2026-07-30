# Starting a new project with this harness

`README.md` tells you how to install the seven agents. `PIPELINE.md` tells
you how to run one task through them. This file covers the layer between:
**what has to exist before task #1 can run at all**, in what order, and
which project-specific assets are worth building (and which are not).

It ends with a worked example — a real run, including the mistakes made
during it — rather than a hypothetical one.

## The problem this solves

Installing the agents takes five minutes. Then you type "use the
product-manager subagent to..." and the pipeline produces something
confident and wrong, because every role reads the consuming project's
`CLAUDE.md` and yours doesn't say anything yet.

The harness ships with **zero opinions about your stack** — that's
deliberate, it's what makes it reusable. The consequence is that a fresh
install is an empty vessel. Bootstrapping is the work of filling it, and
it has a dependency order that isn't obvious.

## What blocks what

```
.gitignore ─────────────────► everything (a leaked key is unrecoverable)
permissions.deny + hook ────► any agent that can run Bash
CLAUDE.md ──────────────────► every role — they all read it, every time
  ├─ canon order ───────────► how conflicts get resolved
  ├─ required-reading paths ► whether documents are reachable at all
  ├─ ubiquitous language ───► whether agentic search finds half your code
  └─ mechanical rules ──────► (but the mechanisms need scaffolding — see below)
blocking decisions (ADRs) ──► Architect, Designer
visual SSOT ────────────────► every UI implementation task
scaffolding ────────────────► the command table being real
                            ► the mechanical rules being writable at all
```

Two of these deserve their own note.

### The mechanical-rules cycle

`CLAUDE.md` should pair each prose rule with its mechanical form (an ESLint
rule, an env check that fails the build, an assertion). But you cannot write
an ESLint rule before the project is scaffolded, and scaffolding is itself a
task, and tasks read `CLAUDE.md`. That's circular.

Resolve it by **declaring the mechanism before it exists, with a status
column**:

| Rule | Mechanical form | Status |
|---|---|---|
| No `window.alert` | ESLint `no-alert` | **not yet implemented** |
| Secret must not reach the client | ESLint path restriction | **not yet implemented** |
| Agents don't run git writes | `permissions.deny` + hook | implemented |

A declared-but-missing mechanism is a **tracked gap**. An undeclared one is
an omission nobody will ever notice. The first task that touches the
relevant area stands its mechanism up, and updates the status.

> A rule with a mechanical form and no mechanism is a rule you have decided
> to violate later.

### Task #1 is usually not the feature you want

For anything with a user interface, the pipeline will refuse to implement
visual requirements when no approved visual artifact exists — a deliberate
stop (`agents/developer.md`). So task #1 is the mock that produces that
artifact, and the feature is task #2.

Generalised: **task #1 is whatever makes task #2 verifiable.** On a backend
project that might be the scaffolding plus one end-to-end path and the
mechanisms that go with it. It is almost never the thing you actually want
built, and resisting that is how projects arrive at "all units complete,
tests green, nothing works."

## Phase 0 — bootstrap, in dependency order

**1. `.gitignore`, before any code exists.** Include `.env*` and
`.claude-dev-team/workspace/`. Do this first because a committed secret is
not fixable by a later commit.

**2. The git guardrails.** `permissions.deny` in `.claude/settings.json`
plus the `PreToolUse` hook (`README.md` steps 2–3). Both — they fail
differently. Test the hook by piping a payload through it and checking it
exits 2; a guardrail that fails open reads as protection while providing
none.

**3. `docs/adr/`, `docs/design/`, `docs/archive/`.** Empty directories with
a `README.md` in each explaining what belongs there. `docs/archive/` must
say, in its own text, that it is off the implementation reading path.

**4. Copy `DOCUMENT-POLICY.md` and `PIPELINE.md` into the project.** Do not
cite them across repositories. An agent running in your project cannot read
a path in the harness repo, and by the policy's own rule an unreachable
document does not exist. (This one was got wrong on the first real run —
see the mistake log below.)

**5. `CLAUDE.md`.** The load-bearing one. At minimum:

- **Canon order**, as a numbered list, stating explicitly that visual
  artifacts outrank prose when they disagree — and that `docs/archive/` is
  not in the ordering at all.
- **"An unspecified requirement is an incomplete ticket, not a licence to
  decide."** Verbatim. This single line does more work than anything else
  in the file.
- **Required reading as literal paths.** "See the design docs" is not
  reachable; `docs/design/` is.
- **Ubiquitous language** — one fixed spelling per domain concept, used in
  identifiers *and* comments. Inconsistent naming makes agentic search miss
  half a codebase silently, and it does so without any error.
- **Mechanical rules with status**, per the cycle above.
- **Quality-gate commands**, marked **unverified** if nothing is scaffolded
  yet, with the first task owning the job of making them real.
- **Definition of done** — for greenfield work, a screenshot of the running
  feature, not "tests green." Every defect on a new project is
  unimplemented-or-initial rather than a regression, so heavier regression
  testing prevents none of them.
- **What not to touch** — the spec, `.env*`, anything above the project root.

**6. Resolve the decisions that block roles from starting.** Design
direction, framework choices left open in the spec, anything the spec marks
as undecided. Record each as an ADR rather than by editing the spec: the
canon order already puts ADRs above the spec, so a higher-ranked document
supersedes an open question without rewriting a file agents are told not to
touch.

When you write these, watch for a specific self-contradiction: an ADR that
says a thing is *undecided* and also that it is *not the implementer's to
decide* leaves nobody able to start. If a decision is genuinely the human's
but you don't want to make it now, say **"propose, then approve at the
gate"** — that is a workflow, not a gap.

**7. `00_request.md` for task #1.** Then `PIPELINE.md` takes over.

## Skills and project rules: when to write them, and when not to

The recurring instinct is to write a skill for everything. Resist it, and
use this ordering:

| You want to enforce… | Use | Not |
|---|---|---|
| A constraint | a **mechanism** (lint rule, build-failing check, assertion) | a skill saying "remember to…" |
| A role's judgment and outputs | an **agent** (already in `agents/`) | a duplicate skill |
| Always-loaded context | **`CLAUDE.md`** | a skill |
| A repeated manual procedure with a slot already in the process | a **skill** | — |

Only the last row is a skill. And note the qualifier: **the process has to
have a slot for it first.**

The evidence for that qualifier is unpleasant. The project this harness
learned from had a Playwright skill installed from early on, and shipped
with three approved screens never built, because nothing in its definition
of done ever called for looking at a screen. From its own retrospective:

> The tool was there from the start. It simply was never built into the
> process.

So the order is **create the slot in the process, then write the skill as
its implementation** — never the reverse. A skill with no slot is a tool
nobody reaches for.

Concretely, the first skill worth writing on most UI projects is
screenshot-capture-and-compare (drive the app, capture the states named in
`docs/design/`, diff them). It is worth writing **after** the visual SSOT
exists, because before that there is nothing to compare against.

### Keep the harness project-agnostic

Project-specific assets — `CLAUDE.md`, mechanisms, skills, ADRs — live in
the project. Nothing about your stack belongs in this repo. The moment it
does, this stops being a reusable asset and becomes one project's tooling.

## Worked example: ViDico

A local-first PWA (Next.js, TypeScript, Tailwind, shadcn) that turns a
photograph into English phrases at a chosen style and level. Starting
state: a specification document, an empty repository, no code.

**Bootstrap, in the order it actually happened:**

1. `.gitignore` written before any code — `.env*` first, so the API key
   could not be committed by accident later.
2. `permissions.deny` + hook installed; hook verified blocking
   `git push --force` (exit 2).
3. `docs/adr/`, `docs/design/`, `docs/archive/` created, each with a README.
   `docs/design/`'s README recorded, as a known risk, that it was **empty** —
   so the spec's visual requirements had nothing to be verified against.
4. `CLAUDE.md` written: canon order, the incomplete-ticket rule, required
   reading as paths, a ubiquitous-language table (`deck`, `card`, `style`,
   `level`, `analysis`, `paraphrase`, `speak`), six mechanical rules of which
   five were marked not-yet-implemented, and a command table marked
   **unverified** because nothing was scaffolded.
5. The spec left the design direction open across three named options. That
   blocks the Designer, so it was decided by the human and recorded as
   **ADR-001** rather than by editing the spec.
6. Task #1 was scoped as **the static mock**, not the feature — UI only,
   placeholder content, no API, no persistence — because until its
   screenshots are approved and promoted to `docs/design/`, every visual
   requirement in the project is unverifiable and would therefore silently
   never get built.

**What the pipeline then caught that the humans had missed.** The Product
Manager returned `Needs human input` with five open questions rather than
proceeding. Two were sharp enough to be worth reproducing:

- Canonising only the prose result view would leave the tag-format view with
  no visual correct-answer — *reproducing, for that one view, exactly the
  failure the task existed to prevent*.
- Omitting the accent-colour state would leave ADR-001's own strongest
  stated rationale unverified.

Both were adopted. That is the incomplete-ticket rule paying for itself on
its first run: the alternative was an agent quietly picking one view,
building something reasonable, and nobody noticing until the feature was
missing months later.

## Mistakes made during that bootstrap

Recorded because a checklist is only as good as the failures behind it.

**Citing a document across repositories.** The project's `.gitignore`
referenced `DOCUMENT-POLICY.md` in *this* repo. An agent running in the
project cannot reach that path, which is a direct violation of the policy's
own reachability rule. Fixed by copying the file in; now step 4 above.

**An ADR that blocked its own implementation.** ADR-001 listed grey steps
and spacing as *undecided* and simultaneously as *not the Designer's to
decide*, leaving nobody able to start. Fixed by restating them as
"propose, then approve at the gate."

**Scope of the mechanisms left out of the request.** `00_request.md` didn't
say which of the five unimplemented mechanical rules this task should stand
up. Caught at the plan gate rather than by the request — recoverable, but it
should have been in the request.

**Running the session from the wrong root.** The harness was installed into
the project, but the Claude Code session was rooted in a *different*
directory, so the project's agents, `permissions.deny`, and hooks were all
unloaded. Everything appeared to work; none of the guardrails were active.
**Root your session at the project directory** before any stage that writes
code.

**A guardrail that failed open.** Earlier, and worth repeating here: the git
hook exited 0 when `jq` was missing, silently disabling itself on every
machine without `jq`. The patterns were correct and had been tested in
isolation; the plumbing ahead of them had not been tested end to end. Test
every hook through its real entry point, in the environment it will run in.

## Checklist

Phase 0:

- [ ] `.gitignore` covers `.env*` and `.claude-dev-team/workspace/`
- [ ] `permissions.deny` set, hook installed, **hook verified blocking**
- [ ] `docs/adr/`, `docs/design/`, `docs/archive/` exist, each with a README
- [ ] `DOCUMENT-POLICY.md` and `PIPELINE.md` copied into the project
- [ ] `CLAUDE.md`: canon order · incomplete-ticket rule · reading paths ·
      ubiquitous language · mechanical rules with status · gate commands
      (marked unverified if nothing is scaffolded) · DoD · what not to touch
- [ ] Blocking decisions recorded as ADRs, each one actionable rather than
      merely stated
- [ ] Session rooted at the project directory

Task #1:

- [ ] Is whatever makes task #2 verifiable — not the feature you want
- [ ] Names which mechanisms it stands up
- [ ] Owns making the command table real
- [ ] Its definition of done requires a screenshot of the running thing
