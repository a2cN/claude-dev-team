#!/usr/bin/env python3
"""token-report.py — token usage per stage, from Claude Code session
transcripts, ready to paste into STATUS.md's Event Log.

Design: design/measurement.md (sections 5 and 6). How to run: LOGGING.md.

Claude Code writes every session to
    ~/.claude/projects/<project>/<session-id>.jsonl
and every subagent that session spawns to its own file,
    ~/.claude/projects/<project>/<session-id>/subagents/agent-<id>.jsonl
with a sibling agent-<id>.meta.json whose "agentType" names the role.

One subagent file is one stage (design D3). Responses in the session file
itself are the orchestrator's own cost. The run is the window between the
Event Log's run-start and run-end, given as --since/--until.

The one trap: a single API response is written as several transcript
records (one per content block), and every one of them repeats the same
`usage`. Responses are deduplicated by requestId; summing records instead
overcounts, by roughly 2x in the transcript this was written against.

Model check (T-14): each stage's actual model is compared with the
`model:` line in the role's definition, <agents-dir>/<role>.md (default
.claude/agents). An alias (opus, sonnet, haiku, fable) matches any model
id of that family; a full id must match exactly; `inherit` or no line is
reported as unspecified. Mismatches are also warned on stderr. The exit
status stays 0: this reports, it does not gate.

Usage:
    token-report.py SESSION.jsonl [SESSION.jsonl ...]
                    [--since ISO8601] [--until ISO8601] [--format md|log]
                    [--agents-dir DIR]

Standard library only. Reads transcripts; writes only to stdout. The
output holds counts, never transcript content.
"""

import argparse
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone

# Weight of each token type relative to one uncached input token, from
# Anthropic's published pricing (design/measurement.md, 6.1 and D4). The
# ratios are the same across current models; absolute prices are not used.
# If pricing changes, change this table and the design doc together.
WEIGHTS = {
    "input": 1.0,
    "cacheCreation5m": 1.25,
    "cacheCreation1h": 2.0,
    "cacheRead": 0.1,
    "output": 5.0,
}
FIELDS = ("input", "output", "cacheRead", "cacheCreation5m", "cacheCreation1h")
MODEL_ALIASES = ("opus", "sonnet", "haiku", "fable")


def parse_ts(value):
    if not value:
        return None
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def split_usage(usage):
    """Map a raw `usage` block onto FIELDS."""
    total_cc = int(usage.get("cache_creation_input_tokens") or 0)
    detail = usage.get("cache_creation") or {}
    cc1h = int(detail.get("ephemeral_1h_input_tokens") or 0)
    cc5m = int(detail.get("ephemeral_5m_input_tokens") or 0)
    if cc1h + cc5m != total_cc:
        # No breakdown recorded: count it at the cheaper, default TTL.
        cc5m, cc1h = total_cc, 0
    return {
        "input": int(usage.get("input_tokens") or 0),
        "output": int(usage.get("output_tokens") or 0),
        "cacheRead": int(usage.get("cache_read_input_tokens") or 0),
        "cacheCreation5m": cc5m,
        "cacheCreation1h": cc1h,
    }


def ieq(counts):
    return round(sum(counts[f] * WEIGHTS[f] for f in FIELDS))


class Bucket:
    def __init__(self, scope, role):
        self.scope, self.role = scope, role
        self.counts = defaultdict(int)
        self.requests = 0
        self.models = Counter()
        self.start = None

    def add(self, counts, model, ts):
        self.requests += 1
        self.models[model] += 1
        for f in FIELDS:
            self.counts[f] += counts[f]
        if ts is not None and (self.start is None or ts < self.start):
            self.start = ts

    def model(self):
        return "+".join(m for m, _ in self.models.most_common()) or "none"


def transcripts_for(session_path):
    """Yield (path, role-or-None) for a session file and its subagents."""
    yield session_path, None
    base = session_path[: -len(".jsonl")] if session_path.endswith(".jsonl") else session_path
    for path in sorted(glob.glob(os.path.join(base, "subagents", "**", "*.jsonl"), recursive=True)):
        role = "unknown"
        try:
            with open(path[: -len(".jsonl")] + ".meta.json", encoding="utf-8") as fh:
                role = json.load(fh).get("agentType") or role
        except (OSError, ValueError):
            pass
        yield path, role


def collect(paths, since, until):
    orchestration = Bucket("orchestration", "ORCHESTRATOR")
    stages = []
    seen = set()
    skipped = 0
    for session in paths:
        if not os.path.isfile(session):
            sys.exit("token-report: no such transcript: %s" % session)
        for path, role in transcripts_for(session):
            bucket = orchestration if role is None else Bucket("stage", role)
            with open(path, encoding="utf-8") as fh:
                for line in fh:
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        skipped += 1
                        continue
                    msg = rec.get("message")
                    if not isinstance(msg, dict) or not isinstance(msg.get("usage"), dict):
                        continue
                    key = rec.get("requestId") or msg.get("id")
                    if key is None or key in seen:
                        continue
                    ts = parse_ts(rec.get("timestamp"))
                    if ts is not None and ((since and ts < since) or (until and ts > until)):
                        continue
                    seen.add(key)
                    bucket.add(split_usage(msg["usage"]), msg.get("model") or "unknown", ts)
            if role is not None and bucket.requests:
                stages.append(bucket)
    # rev = order of invocation within a role (design 2: a second invocation
    # of the same role is a separate stage).
    epoch = datetime.min.replace(tzinfo=timezone.utc)
    stages.sort(key=lambda b: b.start or epoch)
    per_role = Counter()
    for b in stages:
        per_role[b.role] += 1
        b.rev = per_role[b.role]
    return orchestration, stages, skipped


def expected_model(agents_dir, role):
    """The `model:` value in <agents_dir>/<role>.md's frontmatter, or None."""
    try:
        with open(os.path.join(agents_dir, role + ".md"), encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    m = re.match(r"---\n(.*?)\n---", text, re.S)
    if not m:
        return None
    for line in m.group(1).splitlines():
        key, _, value = line.partition(":")
        if key.strip() == "model":
            return value.strip().strip("'\"") or None
    return None


def model_matches(expected, actual):
    if expected in MODEL_ALIASES:
        return actual.startswith("claude-%s-" % expected)
    return actual == expected


def check_models(stages, agents_dir):
    """(stage, expected, result) per stage; result is match|mismatch|unspecified."""
    results = []
    for b in stages:
        expected = expected_model(agents_dir, b.role)
        if expected is None or expected == "inherit":
            result = "unspecified"
        elif all(model_matches(expected, m) for m in b.models):
            result = "match"
        else:
            result = "mismatch"
        results.append((b, expected or "none", result))
    return results


def total_of(buckets):
    t = Bucket("run", "ORCHESTRATOR")
    for b in buckets:
        t.requests += b.requests
        t.models.update(b.models)
        for f in FIELDS:
            t.counts[f] += b.counts[f]
    return t


def fields_kv(b):
    return " ".join("%s=%d" % (f, b.counts[f]) for f in FIELDS) + \
        " requests=%d ieq=%d" % (b.requests, ieq(b.counts))


def run_model_result(checks):
    results = {r for _, _, r in checks}
    if "mismatch" in results:
        return "mismatch"
    if results <= {"match"} and results:
        return "match"
    return "unspecified" if results <= {"unspecified"} else "partial"


def render_log(orchestration, stages, checks):
    """One Event Log event per line (design 4.2, events `tokens` and `model-check`)."""
    lines = []
    for b in stages:
        lines.append("tokens scope=stage stage=%s rev=%d model=%s %s"
                     % (b.role, b.rev, b.model(), fields_kv(b)))
    lines.append("tokens scope=orchestration model=%s %s" % (orchestration.model(), fields_kv(orchestration)))
    lines.append("tokens scope=run stages=%d %s" % (len(stages), fields_kv(total_of(stages + [orchestration]))))
    for b, expected, result in checks:
        lines.append("model-check scope=stage stage=%s rev=%d expected=%s actual=%s result=%s"
                     % (b.role, b.rev, expected, b.model(), result))
    # The orchestrator has no definition to check against; several models
    # here means the main session was switched (/model) during the run.
    lines.append("model-check scope=orchestration models=%s result=%s"
                 % (orchestration.model(), "switched" if len(orchestration.models) > 1 else "single"))
    lines.append("model-check scope=run stages=%d mismatches=%d result=%s"
                 % (len(checks), sum(r == "mismatch" for _, _, r in checks), run_model_result(checks)))
    return "\n".join(lines)


def render_md(orchestration, stages, checks):
    head = ["Start (UTC)", "Stage", "rev", "Model", "requests"] + list(FIELDS) + ["ieq"]
    rows = ["| " + " | ".join(head) + " |", "|" + "---|" * 4 + "---:|" * (len(head) - 4)]

    def row(start, stage, rev, b):
        cells = [start, stage, rev, b.model(), str(b.requests)] + \
            [str(b.counts[f]) for f in FIELDS] + [str(ieq(b.counts))]
        rows.append("| " + " | ".join(cells) + " |")

    for b in stages:
        row(b.start.strftime("%Y-%m-%d %H:%M:%S") if b.start else "?", b.role, str(b.rev), b)
    row("", "(orchestration)", "", orchestration)
    row("", "**run total**", "", total_of(stages + [orchestration]))
    checks_rows = ["| Stage | rev | Expected | Actual | Result |", "|---|---:|---|---|---|"]
    for b, expected, result in checks:
        checks_rows.append("| %s | %d | %s | %s | %s |" % (b.role, b.rev, expected, b.model(), result))
    checks_rows.append("| (orchestration) | | | %s | %s |"
                       % (orchestration.model(), "switched" if len(orchestration.models) > 1 else "single"))
    return "\n".join(rows) + "\n\nieq = input-equivalent tokens; weights: " + \
        ", ".join("%s x%g" % (f, WEIGHTS[f]) for f in FIELDS) + \
        "\n\nModel check (expected = `model:` in the role's definition)\n\n" + "\n".join(checks_rows)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("sessions", nargs="+", help="session transcript(s), <session-id>.jsonl")
    ap.add_argument("--since", help="the run's run-start time (ISO 8601)")
    ap.add_argument("--until", help="the run's run-end time (ISO 8601)")
    ap.add_argument("--format", choices=("md", "log"), default="md",
                    help="md: table to read; log: lines to paste into the Event Log")
    ap.add_argument("--agents-dir", default=os.path.join(".claude", "agents"),
                    help="where the role definitions are, for the model check (default: .claude/agents)")
    args = ap.parse_args()
    orchestration, stages, skipped = collect(args.sessions, parse_ts(args.since), parse_ts(args.until))
    checks = check_models(stages, args.agents_dir)
    print(render_md(orchestration, stages, checks) if args.format == "md"
          else render_log(orchestration, stages, checks))
    for b, expected, result in checks:
        if result == "mismatch":
            print("token-report: model mismatch: %s rev=%d expected %s, ran on %s"
                  % (b.role, b.rev, expected, b.model()), file=sys.stderr)
    if skipped:
        print("token-report: skipped %d unparseable line(s)" % skipped, file=sys.stderr)


if __name__ == "__main__":
    main()
