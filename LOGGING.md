# Logging and measurement

What this harness measures, where the numbers come from, and what must
never be written down. It exists because "make the pipeline cheaper" and
"make it better" are claims, and a claim with no baseline cannot be
checked: you can only say a change helped if the same numbers were taken
before it.

Two numbers are recorded per run, both in `STATUS.md`'s Event Log:

| What | Who records it | Where the number comes from |
|---|---|---|
| Tokens, by type (input / output / cacheRead / cacheCreation), by role and model | Whoever drives the pipeline (role `ORCHESTRATOR`) | `scripts/claude-dev-team/token-report.py` over the session transcripts |
| Why each REJECT happened (`spec` / `misalignment` / `verification` / `impl-bug`) | QA | `60_qa_report.md`'s Defects table — see `agents/quality-assurance.md`, "Failure tags" |

Everything else a retrospective wants — rework cycles, gate decisions,
escalations — is already in the Event Log.

## Tokens: the source is the session transcript

Claude Code writes every session to disk, whether or not anything is
configured:

```
~/.claude/projects/<project-path-with-dashes>/<session-id>.jsonl
~/.claude/projects/<project-path-with-dashes>/<session-id>/subagents/agent-<id>.jsonl
~/.claude/projects/<project-path-with-dashes>/<session-id>/subagents/agent-<id>.meta.json
```

Every API response in those files carries a `usage` block with the four
token types and the model. Each subagent the session spawned has its own
file, and its `meta.json` names the subagent (`"agentType": "developer"`).
That is everything the metrics need — per role, per model, per type —
with nothing to install.

```bash
# whole run (required, before the completion gate)
python3 scripts/claude-dev-team/token-report.py \
    ~/.claude/projects/<project>/<session-id>.jsonl --format line

# one stage (recommended): from the moment the stage was started
python3 scripts/claude-dev-team/token-report.py \
    ~/.claude/projects/<project>/<session-id>.jsonl \
    --since 2026-10-12T04:00:00Z --format line

# a table by role x model, to read rather than paste
python3 scripts/claude-dev-team/token-report.py ~/.claude/projects/<project>/<session-id>.jsonl
```

Pass several session files if the run spanned several sessions. Paste the
`--format line` output verbatim into the Event Log as an `ORCHESTRATOR`
entry; the template's comments say which entries are required.

### The double-count trap

A single API response is written as several transcript records — one per
content block (thinking, text, each tool call) — and **every record repeats
the full `usage` of the response.** Summing records rather than responses
overcounts; in the transcript this script was written against, 72 of 118
responses were split this way. `token-report.py` deduplicates by
`requestId`. Any other tool you point at these files has to do the same.

### Reading the numbers

- **Do not judge by the grand total.** `cacheRead` dominates it and is
  billed at a small fraction of `input`. Compare each type separately, and
  `cacheCreation` and `output` before the rest.
- **Compare stages, not tasks.** Tasks differ in size; a stage of one task
  is closer in shape to the same stage of another. That is why per-stage
  entries are recommended.
- **One run proves nothing.** The same prompt produces different runs.
  Keep a change only if it holds over the next few comparable tasks without
  the quality signals (human rework at the completion gate, defects found
  after merge) getting worse.
- **Spawning a subagent has a fixed cost.** A subagent that ran no tools
  and answered one word still cost about 13k tokens of cache creation
  (system prompt and tool definitions). Many small stages pay it many
  times.

### Why not OpenTelemetry

Claude Code can export metrics over OpenTelemetry
(`CLAUDE_CODE_ENABLE_TELEMETRY=1`, metric `claude_code.token.usage`). It is
the right tool for a team with a collector. For this harness it is worse
on every axis that matters:

- it reports a custom subagent's name as `custom` unless
  `OTEL_LOG_TOOL_DETAILS=1` is set — which also exports tool details;
- there is no file exporter, so you need either a collector or the
  `console` exporter, whose output lands in the terminal of an interactive
  session;
- it must be switched on *before* the run, so a forgotten variable is a
  lost baseline. The transcripts are written regardless.

If you already run a collector, use it; the numbers should agree with the
script's. Otherwise don't add one for this.

## What must never be recorded

The transcripts contain everything: prompts, file contents, command output,
anything a tool read. Treat them as secret.

- **Never copy a transcript, or any excerpt of one, into the repository**,
  the workspace, an issue or a PR. Only the counts `token-report.py` prints
  leave `~/.claude/`.
- Never put secrets, keys, environment values or personal data into an
  Event Log entry. Entries are archived to `docs/archive/` and committed.
- If the project's docs live in a public repository, check that even the
  counts are something you are content to publish.

## Requirements

`token-report.py` needs Python 3.8+ and the standard library only. It reads
the files it is given and writes only to stdout.
