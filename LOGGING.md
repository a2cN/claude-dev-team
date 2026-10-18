# Logging and measurement

What this harness measures, where the numbers come from, and what must
never be written down. It exists because "make the pipeline cheaper" and
"make it better" are claims, and a claim with no baseline cannot be
checked: you can only say a change helped if the same numbers were taken
before it.

Two kinds of number are recorded per run, both in `STATUS.md`'s Event Log.
Why these and not others, and every choice behind them, is in
`design/measurement.md`.

| What | Who records it | Where the number comes from |
|---|---|---|
| Tokens per stage and per run: five raw counts (input / output / cacheRead / cacheCreation 5m / 1h) and `ieq` | Whoever drives the pipeline (role `ORCHESTRATOR`) | `scripts/claude-dev-team/token-report.py` over the session transcripts |
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

One subagent file is one stage, so the stages split themselves; the only
times you supply are the run's start and end, from the Event Log's
`run-start` and `run-end` lines (design/measurement.md, D3).

```bash
# at run-end: lines to paste into the Event Log, one `tokens` entry each
python3 scripts/claude-dev-team/token-report.py \
    ~/.claude/projects/<project>/<session-id>.jsonl \
    --since <run-start time> --until <run-end time> --format log

# the same, as a table to read
python3 scripts/claude-dev-team/token-report.py \
    ~/.claude/projects/<project>/<session-id>.jsonl \
    --since <run-start time> --until <run-end time>
```

The log format prints one `tokens scope=stage` line per subagent
invocation (role, rev in invocation order, model, five raw counts, `ieq`),
one `tokens scope=orchestration` line for the driving session itself, and
one `tokens scope=run` line for the total. It then prints `model-check`
lines: each stage's actual model against the `model:` in
`.claude/agents/<role>.md` (`--agents-dir` to change; an alias such as
`sonnet` matches any model of that family), whether the orchestrator's own
session switched models mid-run, and a run-level `result=match|mismatch|
partial`. A mismatch is also warned on stderr; the exit status stays 0. Pass several session files if
the run spanned several sessions. Do this at run-end, not later: Claude
Code deletes session transcripts after 30 days by default
(`cleanupPeriodDays`), and a run that was not logged by then is gone.

**One run per session at a time.** Two runs in one session overlap in
time and cannot be told apart.

### The double-count trap

A single API response is written as several transcript records — one per
content block (thinking, text, each tool call) — and **every record repeats
the full `usage` of the response.** Summing records rather than responses
overcounts; in the transcript this script was written against, 72 of 118
responses were split this way. `token-report.py` deduplicates by
`requestId`. Any other tool you point at these files has to do the same.

### Reading the numbers

- **Judge by `ieq`, never by the raw sum.** `ieq` (input-equivalent
  tokens) weights each type by its price relative to uncached input:
  output x5, cache write x1.25 (5-minute) or x2 (1-hour), cache read x0.1.
  The raw sum is dominated by cache reads, which are cheap, and points at
  the wrong thing to cut. The raw counts stay beside it so a shift hidden
  by the weights can still be seen.
- **Compare stages of the same role and model, not tasks.** Tasks differ
  in size; a stage of one task is closer in shape to the same stage of
  another. `ieq` does not include the price difference between models.
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
