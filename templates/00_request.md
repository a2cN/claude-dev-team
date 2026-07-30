<!--
  Template for 00_request.md — the first artifact in a Claude Dev Team
  task workspace. Copy this file to:
    .claude-dev-team/workspace/<task-slug>/00_request.md
  and fill it in yourself (or dictate it to your main Claude Code session
  and have it write the file — this is the one artifact in the pipeline
  that is NOT produced by a subagent; it's the human's statement of intent
  that the rest of the pipeline works from).

  Keep it short. This is a raw request, not a spec — the Product Manager
  agent turns it into 10_product_brief.md.
-->

# Request: <short task title>

**Task slug:** `<task-slug>`  <!-- must match the workspace directory name -->
**Requested by:** <name / email>
**Date:** <YYYY-MM-DD>

## What I want

<Plain-language description of the problem or feature. Write it the way
you'd explain it to a teammate, not as a formal spec.>

## Why

<Why this matters right now — user pain, business reason, bug impact, etc.
Optional but helps the Product Manager prioritize honestly.>

## Constraints / non-negotiables (if any)

- <e.g. "must ship behind a feature flag", "no new npm dependencies",
  "must not touch the billing module">

## Known context

<Links, related tickets, prior discussion, screenshots — anything the
Product Manager and later roles shouldn't have to rediscover.>

## Out of scope (if you already know)

<Anything you explicitly do NOT want done as part of this request.>
