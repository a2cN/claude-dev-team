# Claude Dev Team

A reusable, project-agnostic "small dev team" of seven Claude Code
subagents, wired together by a file-based pipeline instead of by direct
agent-to-agent calls (which Claude Code subagents can't reliably do — see
`PIPELINE.md`). Drop it into any project — Next.js, Flutter, Laravel,
whatever — and it plugs into that project's own conventions rather than
bringing any of its own.

The seven roles:

| Role | File | Model tier | Job |
|---|---|---|---|
| Product Manager | `agents/product-manager.md` | Opus | Turns a raw request into a scoped product brief |
| Project Manager | `agents/project-manager.md` | Opus | Plans, estimates, tracks status, tells you what to run next |
| Solution Architect | `agents/solution-architect.md` | Opus | Designs the technical approach |
| Designer | `agents/designer.md` | Opus | UX flows, states, component specs (only for tasks with a UI surface) |
| Developer | `agents/developer.md` | Sonnet | Implements, runs real quality gates, reports verbatim |
| Quality Assurance | `agents/quality-assurance.md` | Sonnet | Independently re-verifies — never trusts the Developer's self-report |
| Process Advisor | `agents/process-advisor.md` | Opus | Independent, candid feedback on how the *process* is working — not part of the delivery chain, no approval authority |

Full mechanics — the artifact pipeline, the human gates, the QA rejection
loop, and a literal step-by-step "what do I type" walkthrough — are in
`PIPELINE.md`. Read that before running your first task; this file is
just install + a worked example.

## What this assumes about Claude Code

This was written and checked against the current Claude Code subagent
system as of mid-2026: subagent files are Markdown with YAML frontmatter
(`name`, `description` required; `tools`, `model`, `hooks`, and others
optional), placed in `.claude/agents/` (project-scoped) or
`~/.claude/agents/` (user-scoped). The `model` field accepts `opus`,
`sonnet`, `haiku`, a full model ID, or `inherit`. Full reference:
https://code.claude.com/docs/en/sub-agents

The one constraint this whole harness is built around: **a subagent
cannot reliably invoke another subagent in an automatic chain.**
Orchestration between the seven roles here is either driven by you, the
human operator, turn by turn (the default, and what `PIPELINE.md`
assumes), or by running the Project Manager as the main session via
`claude --agent project-manager` (an advanced, optional pattern, also
covered in `PIPELINE.md`). If a future Claude Code version changes this
constraint, the file-based handoff still works unmodified — it just
becomes optional rather than necessary.

## Install into a project

1. Copy the `agents/` directory's seven files into that project's
   `.claude/agents/` (create it if it doesn't exist):

   ```bash
   mkdir -p /path/to/your-project/.claude/agents
   cp agents/*.md /path/to/your-project/.claude/agents/
   ```

2. Copy the git-write guardrail hook and make it executable:

   ```bash
   mkdir -p /path/to/your-project/.claude/hooks/claude-dev-team
   cp hooks/block-git-write.sh /path/to/your-project/.claude/hooks/claude-dev-team/
   chmod +x /path/to/your-project/.claude/hooks/claude-dev-team/block-git-write.sh
   ```

   The four agents that carry `Bash` access
   (`project-manager`, `solution-architect`, `developer`,
   `quality-assurance`) already reference this exact path in their
   frontmatter `hooks` field, so no further wiring is needed once the file
   exists there.

3. Add the stronger, non-heuristic guardrail to that project's
   `.claude/settings.json` (create the file if it doesn't exist; merge
   into `permissions.deny` if it already has entries):

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

   See `PIPELINE.md`'s "Setting up the git guardrail" section for why
   both the hook and this setting matter — they cover different failure
   modes.

4. Make sure that project's `CLAUDE.md` defines what these agents need to
   plug into (see next section). This harness ships with zero opinions
   about tech stack — every agent reads the consuming project's own
   `CLAUDE.md` for that.

5. Copy the two starter templates somewhere handy (they're not required
   at any fixed path, just convenient to have around):

   ```bash
   mkdir -p /path/to/your-project/.claude-dev-team/templates
   cp templates/00_request.md templates/STATUS.md /path/to/your-project/.claude-dev-team/templates/
   ```

6. Set up the document policy — **read `DOCUMENT-POLICY.md` first**, it
   explains why each of these matters. Concretely:

   ```gitignore
   # in the project's .gitignore
   .claude-dev-team/workspace/
   ```

   ```bash
   mkdir -p /path/to/your-project/docs/adr /path/to/your-project/docs/design
   cp DOCUMENT-POLICY.md PIPELINE.md /path/to/your-project/.claude-dev-team/
   ```

   Copy the two docs in, don't just cite them: an agent running inside the
   consuming project cannot reach a path in *this* repo, and by this
   policy's own rule an unreachable document does not exist. `.gitignore`
   only excludes `workspace/`, so these stay committed.

   The pipeline workspace is transient by policy and is not committed. The
   two artifacts that must survive a merge — `30_architecture.md` and
   `40_design_brief.md` — are promoted into `docs/adr/` and `docs/design/`
   at completion, and verification evidence goes into the PR body. Skipping
   this step doesn't break the pipeline; it just silently discards every
   architectural decision and design artifact the moment you merge.

That's it. No build step, no dependency install — these are just markdown
files Claude Code reads at session start (restart your Claude Code session
after step 1 if `.claude/agents/` didn't already exist in that project, so
the new directory gets picked up).

## What your project's `CLAUDE.md` needs to define

Every agent in this harness explicitly reads the consuming project's
`CLAUDE.md` and defers to it rather than assuming anything. At minimum,
it should define:

- **Tech stack**: language(s), framework(s), major libraries — whatever
  the Solution Architect needs to make choices consistent with what's
  already there.
- **Quality gate commands**: the actual commands for lint, typecheck,
  test, and build (whichever apply to this project). Be exact — the
  Developer and QA run these verbatim and treat a missing definition here
  as a reason to stop, not a reason to guess.

  ```markdown
  ## Quality Gates
  - Lint: `npm run lint`
  - Typecheck: `npm run typecheck`
  - Unit tests: `npm test`
  - Build: `npm run build`
  ```

- **Coding conventions**: whatever this project already does for style,
  file organization, error handling, etc. — so the Developer extends
  existing patterns instead of inventing parallel ones.
- **Design system / component library** (if the project has a UI): so the
  Designer extends it rather than inventing a new one.
- **Promoted-artifact paths, named as paths**: `docs/adr/` and
  `docs/design/`, spelled out literally. "See our design docs" is not
  reachable; a path is. Also state that visual artifacts outrank prose when
  the two disagree, and the rule that an unspecified requirement is an
  incomplete ticket rather than a licence to decide. See
  `DOCUMENT-POLICY.md`, "Reachability beats coverage."
- **The project's ubiquitous language**: one fixed spelling per domain
  concept, used in identifiers and comments alike. Agentic search is only
  as good as the vocabulary's consistency.
- **Anything already off-limits**: existing security/permission rules,
  no-prod-deploy policies, modules that need special care. This harness
  is built to layer on top of whatever guardrails already exist, not
  loosen them — but it can only respect a rule that's actually written
  down somewhere it reads.

If your project has none of this documented yet, run the built-in `/init`
command (or write it manually) before adopting this harness — the agents
will tell you explicitly when they can't find something they need rather
than silently guessing, but that's a worse experience than just having it
defined up front.

## Worked example

Say you're adding CSV export to a small internal Next.js admin tool.

```bash
mkdir -p .claude-dev-team/workspace/add-csv-export
cp .claude-dev-team/templates/00_request.md \
   .claude-dev-team/workspace/add-csv-export/00_request.md
# edit that file: "Let admins export the users table as CSV from the
# admin dashboard. Needed because finance keeps asking for manual exports."
```

Then, in your Claude Code session:

```
Use the product-manager subagent to read
.claude-dev-team/workspace/add-csv-export/00_request.md and write the
product brief.
```
```
Use the project-manager subagent to write the project plan for
add-csv-export.
```
Review `20_project_plan.md`, edit `Approval Status` to `APPROVED`.
```
Use the solution-architect subagent to write the architecture for
add-csv-export.
```
The plan marks Design as "not required" (it's an existing admin table
with a new export button, not a new UI surface) — so:
```
Use the developer subagent to implement add-csv-export.
```
```
Use the quality-assurance subagent to review add-csv-export.
```
QA passes.
```
Use the project-manager subagent to draft the completion summary for
add-csv-export.
```
Review `90_completion.md`, review the real diff yourself, edit
`Approval Status` to `APPROVED`. Then you — not an agent — run:
```
git checkout -b add-csv-export
git add app/admin/users/export.ts app/admin/users/page.tsx
git commit -m "Add CSV export for admin users table"
git push
```

Full turn-by-turn detail, including what happens on a QA rejection, is in
`PIPELINE.md`.

## Files in this repo

```
agents/                    7 subagent definitions — copy to .claude/agents/
  product-manager.md
  project-manager.md
  solution-architect.md
  designer.md
  developer.md
  quality-assurance.md
  process-advisor.md
hooks/
  block-git-write.sh        PreToolUse hook — copy to .claude/hooks/claude-dev-team/
templates/
  00_request.md              starter template for the first artifact of a task
  STATUS.md                  starter template for the per-task tracker
PIPELINE.md                  full orchestration spec + turn-by-turn walkthrough
README.md                    this file
CHANGELOG.md                 design decisions, rationale, open questions
```

## Assumptions and known limitations

- The Claude Code subagent frontmatter schema referenced here (`name`,
  `description`, `tools`, `model`, `hooks`, etc.) was verified against
  the live docs at https://code.claude.com/docs/en/sub-agents at the time
  this harness was built. If your Claude Code version is meaningfully
  older or newer, sanity-check the frontmatter against your installed
  version's `/agents` behavior before relying on it.
- Tool grants in this schema are per-tool, not per-path. QA, for example,
  is instructed never to edit source files, but that's enforced by its
  system prompt, not by a structural restriction the way the git-write
  hook is for Bash. See `PIPELINE.md`'s "Known limitations" section.
- The rework-cycle cap and the estimate-overrun threshold are tracked by
  agents reasoning over markdown, not a hard external counter — treat
  `STATUS.md` as the audit trail if you ever suspect a miscount.
- This harness has no opinion on how many of the seven roles a given task
  actually needs. Trivial tasks (a one-line copy fix) will feel
  over-processed by a 7-stage pipeline — that's a legitimate reason to
  skip the harness entirely for that task and just make the change
  directly, not a bug in the harness.
