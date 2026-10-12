#!/usr/bin/env python3
"""token-report.py — token usage per role, model and type, from Claude Code
session transcripts.

Claude Code writes every session to
    ~/.claude/projects/<project>/<session-id>.jsonl
and every subagent that session spawns to
    ~/.claude/projects/<project>/<session-id>/subagents/agent-<id>.jsonl
with a sibling agent-<id>.meta.json whose "agentType" is the subagent's
name (e.g. "developer"). Each API response carries a `usage` block. This
script sums those blocks. See LOGGING.md for why this is the primary
source rather than OpenTelemetry.

The one trap: a single API response is written as several transcript
records (one per content block), and every one of them repeats the same
`usage`. Summing records instead of responses overcounts — by roughly 2x
in the transcript this was written against. Responses are deduplicated by
requestId here.

Usage:
    token-report.py SESSION.jsonl [SESSION.jsonl ...]
                    [--since ISO8601] [--until ISO8601] [--format md|line]

Standard library only. Reads transcripts; writes only to stdout. The
output holds counts, never transcript content, so it is safe to paste into
STATUS.md.
"""

import argparse
import glob
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone

TYPES = (
    ("input", "input_tokens"),
    ("output", "output_tokens"),
    ("cacheRead", "cache_read_input_tokens"),
    ("cacheCreation", "cache_creation_input_tokens"),
)


def parse_ts(value):
    if not value:
        return None
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def transcripts_for(session_path):
    """Yield (path, role) for a session file and every subagent under it."""
    yield session_path, "main"
    base = session_path[: -len(".jsonl")] if session_path.endswith(".jsonl") else session_path
    pattern = os.path.join(base, "subagents", "**", "*.jsonl")
    for path in sorted(glob.glob(pattern, recursive=True)):
        role = "subagent:unknown"
        meta = path[: -len(".jsonl")] + ".meta.json"
        try:
            with open(meta, encoding="utf-8") as fh:
                role = json.load(fh).get("agentType") or role
        except (OSError, ValueError):
            pass
        yield path, role


def collect(paths, since, until):
    totals = defaultdict(lambda: defaultdict(int))  # (role, model) -> type -> n
    seen = set()
    skipped = 0
    for session in paths:
        if not os.path.isfile(session):
            sys.exit("token-report: no such transcript: %s" % session)
        for path, role in transcripts_for(session):
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
                    bucket = totals[(role, msg.get("model") or "unknown")]
                    bucket["requests"] += 1
                    for name, field in TYPES:
                        bucket[name] += int(msg["usage"].get(field) or 0)
    return totals, skipped


def grand_total(totals):
    out = defaultdict(int)
    for bucket in totals.values():
        for k, v in bucket.items():
            out[k] += v
    return out


def render_line(totals):
    t = grand_total(totals)
    roles = sorted({role for role, _ in totals})
    return "Tokens: input=%d output=%d cacheRead=%d cacheCreation=%d (requests=%d; roles=%s)" % (
        t["input"], t["output"], t["cacheRead"], t["cacheCreation"],
        t["requests"], ",".join(roles) or "none")


def render_md(totals):
    cols = ["requests"] + [name for name, _ in TYPES]
    rows = ["| Role | Model | " + " | ".join(cols) + " |",
            "|---|---|" + "---:|" * len(cols)]
    for (role, model) in sorted(totals):
        b = totals[(role, model)]
        rows.append("| %s | %s | " % (role, model) + " | ".join(str(b[c]) for c in cols) + " |")
    t = grand_total(totals)
    rows.append("| **total** | | " + " | ".join(str(t[c]) for c in cols) + " |")
    return "\n".join(rows) + "\n\n" + render_line(totals)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("sessions", nargs="+", help="session transcript(s), <session-id>.jsonl")
    ap.add_argument("--since", help="ignore responses before this ISO 8601 time")
    ap.add_argument("--until", help="ignore responses after this ISO 8601 time")
    ap.add_argument("--format", choices=("md", "line"), default="md")
    args = ap.parse_args()
    totals, skipped = collect(args.sessions, parse_ts(args.since), parse_ts(args.until))
    print(render_md(totals) if args.format == "md" else render_line(totals))
    if skipped:
        print("token-report: skipped %d unparseable line(s)" % skipped, file=sys.stderr)


if __name__ == "__main__":
    main()
