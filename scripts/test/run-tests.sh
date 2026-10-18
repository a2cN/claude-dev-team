#!/usr/bin/env bash
#
# run-tests.sh — exercise verify-dev-team.sh against throwaway repositories.
#
# This harness ships no application code, so "does it work" has to be
# answered somewhere. Each case below builds a real git repository in a
# temporary directory, commits a fixture that models one specific failure
# from the field, and asserts BOTH the exit code AND the id of the check
# that was supposed to catch it. Asserting only the exit code would let a
# check pass for the wrong reason, which is how a green test suite starts
# lying.
#
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
VERIFY="$HERE/../verify-dev-team.sh"
TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/dev-team-tests.XXXXXX")
trap 'rm -rf "$TMPROOT"' EXIT

TESTS=0
FAILURES=0

# ------------------------------------------------------------ fixtures

new_repo() {
    # new_repo <name> -> path, with an empty docs/ tree committed on main
    local repo="$TMPROOT/$1"
    mkdir -p "$repo"
    (
        cd "$repo" || exit 1
        git init -q -b main .
        git config user.email test@example.com
        git config user.name "Test"
        mkdir -p docs/adr docs/design docs/archive
        printf '# Project\n' >README.md
        git add -A
        git commit -qm "base"
        git checkout -qb feature
    )
    printf '%s' "$repo"
}

seed_ledger() {
    # seed_ledger <repo> [row...]
    local repo="$1"; shift
    {
        printf '# Open Decisions\n\n'
        printf '| ID | Raised | By | Task slug | Decision needed | Options | Blocks | Status | Resolution |\n'
        printf '|---|---|---|---|---|---|---|---|---|\n'
        local row
        for row in "$@"; do
            printf '| %s | 2026-09-01 | DESIGNER | demo | a question | a or b | nothing | OPEN | |\n' "$row"
        done
    } >"$repo/docs/OPEN-DECISIONS.md"
}

seed_run() {
    # seed_run <repo> <slug> <date>
    # A complete, correctly finished backend-only run.
    local repo="$1" slug="$2" date="$3"
    local adir="$repo/docs/archive/$date-$slug"
    mkdir -p "$adir"

    printf '# Request\n\nAdd the thing.\n' >"$adir/00_request.md"
    printf '# Product Brief\n\nThe thing is needed.\n' >"$adir/10_product_brief.md"
    cat >"$adir/20_project_plan.md" <<'PLAN'
# Project Plan

## Stages Required
- Product brief: done (10_product_brief.md)
- Architecture: required
- Visual surface: no
- Design: N/A — backend-only change
- Design approval: N/A — no visual surface
- Development: required
- QA: required
- Completion: required

## Human Gate: Plan Approval
**Approval Status:** APPROVED
PLAN
    printf '# Status\n\n- 2026-09-01 — HUMAN — Workspace created.\n' >"$adir/STATUS.md"
    printf '# Architecture\n\nUse a stream.\n' >"$adir/30_architecture.md"
    printf '# Implementation\n\n## Inputs Read\n- docs/adr/001-%s.md\n' "$slug" >"$adir/50_implementation.md"
    printf '# QA Report\n\n## Verdict\nPASS\n' >"$adir/60_qa_report.md"
    cat >"$adir/90_completion.md" <<COMPLETION
# Completion

## Artifacts due for promotion and archiving
| Source | Destination | Rule | Status |
|---|---|---|---|
| 30_architecture.md | docs/adr/001-$slug.md | trimmed, maintained | done |
| **the entire workspace** | **docs/archive/$date-$slug/** | verbatim, immutable | pending |

## Human Gate: Completion Approval
**Approval Status:** APPROVED
COMPLETION

    printf '# ADR 001: %s\n\nUse a stream, because memory.\n' "$slug" >"$repo/docs/adr/001-$slug.md"
    seed_ledger "$repo"
}

commit_all() {
    (cd "$1" && git add -A && git commit -qm "change") || return 1
}

# ------------------------------------------------------------- assertion

run_case() {
    # run_case <name> <repo> <expected-exit> <expected-substring> [env...]
    local name="$1" repo="$2" want_exit="$3" want_text="$4"
    shift 4
    TESTS=$((TESTS + 1))

    local out status
    out=$(cd "$repo" && env "$@" bash "$VERIFY" --base main 2>&1)
    status=$?

    local ok=1
    [ "$status" -eq "$want_exit" ] || ok=0
    if [ -n "$want_text" ] && ! printf '%s' "$out" | grep -qF "$want_text"; then
        ok=0
    fi

    if [ "$ok" -eq 1 ]; then
        printf 'ok   %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
        printf 'FAIL %s\n' "$name"
        printf '     expected exit %s and text %s\n' "$want_exit" "${want_text:-<any>}"
        printf '     got exit %s:\n' "$status"
        printf '%s\n' "$out" | sed 's/^/       /'
    fi
}

# ----------------------------------------------------------------- cases

# 1. The happy path: a complete run, archived and promoted.
repo=$(new_repo clean)
seed_run "$repo" demo 2026-09-01
commit_all "$repo"
run_case "clean run passes" "$repo" 0 "PASS A1" PR_BODY="Dev-Team-Run: demo"

# 2. Issue #1: QA passed, a PR was opened, nothing was archived.
repo=$(new_repo no-archive)
printf 'code\n' >"$repo/app.js"
commit_all "$repo"
run_case "missing archive fails A1" "$repo" 1 "FAIL A1" PR_BODY="Dev-Team-Run: demo"

# 3. Issue #2: archived before the human signed.
repo=$(new_repo unsigned)
seed_run "$repo" demo 2026-09-01
sed -i.bak 's/^\*\*Approval Status:\*\* APPROVED/**Approval Status:** PENDING_HUMAN_APPROVAL/' \
    "$repo/docs/archive/2026-09-01-demo/90_completion.md"
rm -f "$repo/docs/archive/2026-09-01-demo/90_completion.md.bak"
commit_all "$repo"
run_case "unsigned gate in archive fails A3" "$repo" 1 "FAIL A3" PR_BODY="Dev-Team-Run: demo"

# 4. Promotion listed but never performed.
repo=$(new_repo promotion-pending)
seed_run "$repo" demo 2026-09-01
sed -i.bak 's#| trimmed, maintained | done |#| trimmed, maintained | pending |#' \
    "$repo/docs/archive/2026-09-01-demo/90_completion.md"
rm -f "$repo/docs/archive/2026-09-01-demo/90_completion.md.bak"
commit_all "$repo"
run_case "pending promotion row fails B1" "$repo" 1 "FAIL B1" PR_BODY="Dev-Team-Run: demo"

# 5. Promotion marked done, destination absent.
repo=$(new_repo promotion-lying)
seed_run "$repo" demo 2026-09-01
rm -f "$repo/docs/adr/001-demo.md"
commit_all "$repo"
run_case "absent promotion destination fails B2" "$repo" 1 "FAIL B2" PR_BODY="Dev-Team-Run: demo"

# 6. Issue #3: an open question cited by an id with no ledger row.
repo=$(new_repo dangling-id)
seed_run "$repo" demo 2026-09-01
printf '\n## Unverifiable Requirements\n- OD-demo-07 — the loading animation\n' \
    >>"$repo/docs/archive/2026-09-01-demo/60_qa_report.md"
commit_all "$repo"
run_case "dangling ledger id fails C2" "$repo" 1 "FAIL C2" PR_BODY="Dev-Team-Run: demo"

# 6b. The same id, present in the ledger, passes.
repo=$(new_repo resolved-id)
seed_run "$repo" demo 2026-09-01
seed_ledger "$repo" OD-demo-07
printf '\n## Unverifiable Requirements\n- OD-demo-07 — the loading animation\n' \
    >>"$repo/docs/archive/2026-09-01-demo/60_qa_report.md"
commit_all "$repo"
run_case "cited id with a ledger row passes C2" "$repo" 0 "PASS C2" PR_BODY="Dev-Team-Run: demo"

# 7. The archive is immutable: editing an archived file is a defect.
repo=$(new_repo archive-edited)
seed_run "$repo" demo 2026-09-01
commit_all "$repo"
(cd "$repo" && git checkout -q main && git merge -q feature && git checkout -qb feature2)
printf '\nedited after the fact\n' >>"$repo/docs/archive/2026-09-01-demo/00_request.md"
commit_all "$repo"
run_case "editing an archived file fails A6" "$repo" 1 "FAIL A6" PR_BODY="Dev-Team-Run: demo"

# 8. Ledger rows may not be deleted.
repo=$(new_repo ledger-deleted)
seed_run "$repo" demo 2026-09-01
seed_ledger "$repo" OD-demo-01
commit_all "$repo"
(cd "$repo" && git checkout -q main && git merge -q feature && git checkout -qb feature2)
seed_ledger "$repo"
commit_all "$repo"
run_case "deleting a ledger row fails C4" "$repo" 1 "FAIL C4" PR_BODY="Dev-Team-Run: demo"

# 9. A code change with no declaration at all.
repo=$(new_repo undeclared)
printf 'code\n' >"$repo/app.js"
commit_all "$repo"
run_case "undeclared code change fails A0" "$repo" 1 "FAIL A0"

# 10. An explicit "this did not come from the pipeline".
repo=$(new_repo declared-none)
printf 'code\n' >"$repo/app.js"
commit_all "$repo"
run_case "Dev-Team-Run: none is accepted" "$repo" 0 "SKIP A0" PR_BODY="Dev-Team-Run: none"

# 11. Issue #4: a design canon directory with only a brief in it.
repo=$(new_repo design-no-readme)
seed_run "$repo" demo 2026-09-01
mkdir -p "$repo/docs/design/demo"
printf '# Design Brief\n\nThree candidates, recommend C.\n' >"$repo/docs/design/demo/brief.md"
commit_all "$repo"
run_case "design canon without a README fails B3" "$repo" 1 "FAIL B3" PR_BODY="Dev-Team-Run: demo"

# 12. The plan's Design approval line is unreadable.
repo=$(new_repo plan-unreadable)
seed_run "$repo" demo 2026-09-01
sed -i.bak '/Design approval:/d' "$repo/docs/archive/2026-09-01-demo/20_project_plan.md"
rm -f "$repo/docs/archive/2026-09-01-demo/20_project_plan.md.bak"
commit_all "$repo"
run_case "missing Design approval line fails A2" "$repo" 1 "FAIL A2" PR_BODY="Dev-Team-Run: demo"

# 13. Design approval required but the sheet was never archived.
repo=$(new_repo approval-missing)
seed_run "$repo" demo 2026-09-01
sed -i.bak 's/^- Design approval: N\/A.*/- Design approval: required/' \
    "$repo/docs/archive/2026-09-01-demo/20_project_plan.md"
rm -f "$repo/docs/archive/2026-09-01-demo/20_project_plan.md.bak"
commit_all "$repo"
run_case "required approval sheet absent fails A2" "$repo" 1 "FAIL A2" PR_BODY="Dev-Team-Run: demo"

# 14. An unfilled template placeholder reached the archive.
repo=$(new_repo placeholder)
seed_run "$repo" demo 2026-09-01
printf '\nDecided on <YYYY-MM-DD> by the team.\n' \
    >>"$repo/docs/archive/2026-09-01-demo/90_completion.md"
commit_all "$repo"
run_case "unfilled placeholder fails A5" "$repo" 1 "FAIL A5" PR_BODY="Dev-Team-Run: demo"

# 15. The same token inside a fenced block or an HTML comment is fine.
repo=$(new_repo placeholder-exempt)
seed_run "$repo" demo 2026-09-01
{
    printf '\n<!-- the template said <YYYY-MM-DD> here -->\n\n'
    printf '```\n$ date +<YYYY-MM-DD>\n```\n'
} >>"$repo/docs/archive/2026-09-01-demo/90_completion.md"
commit_all "$repo"
run_case "placeholders in comments and fences pass A5" "$repo" 0 "PASS A5" PR_BODY="Dev-Team-Run: demo"

# 16. Slug discovery from the diff when the PR body says nothing.
repo=$(new_repo discover-from-diff)
seed_run "$repo" demo 2026-09-01
commit_all "$repo"
run_case "slug discovered from the diffed archive dir" "$repo" 0 "PASS A1"

# ------------------------------------------------- workspace preflight mode

TESTS=$((TESTS + 1))
ws="$TMPROOT/ws/demo"
mkdir -p "$ws"
printf '# Plan\n\n**Approval Status:** PENDING_HUMAN_APPROVAL\n' >"$ws/20_project_plan.md"
if out=$(bash "$VERIFY" --workspace "$ws" 2>&1) && printf '%s' "$out" | grep -q 'PASS A5'; then
    printf 'ok   workspace preflight ignores an unsigned live gate\n'
else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL workspace preflight ignores an unsigned live gate\n%s\n' "$out" | sed 's/^/       /'
fi

TESTS=$((TESTS + 1))
printf '\nOpen question: <task-slug> was never filled in.\n' >>"$ws/20_project_plan.md"
out=$(bash "$VERIFY" --workspace "$ws" 2>&1)
if [ $? -eq 1 ] && printf '%s' "$out" | grep -q 'FAIL A5'; then
    printf 'ok   workspace preflight catches a placeholder\n'
else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL workspace preflight catches a placeholder\n%s\n' "$out" | sed 's/^/       /'
fi

# A7 (T-15): Event Log times must not go backwards or into the future,
# unless a later line names the wrong time (a correction).
a7_case() {
    # a7_case <name> <want-exit> <want-id-and-level> <event-log-lines>
    local name="$1" want_exit="$2" want="$3" lines="$4" rc
    TESTS=$((TESTS + 1))
    ws="$TMPROOT/ws/a7-$TESTS"
    mkdir -p "$ws"
    printf '# Status\n\n## Event Log\n\n%s\n\n## Derived Summary\n\n- 2099-01-01T00:00:00+09:00 — outside the log\n' "$lines" >"$ws/STATUS.md"
    out=$(bash "$VERIFY" --workspace "$ws" 2>&1)
    rc=$?
    if [ "$rc" -eq "$want_exit" ] && printf '%s' "$out" | grep -q "$want"; then
        printf 'ok   %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
        printf 'FAIL %s (exit %s, want %s)\n%s\n' "$name" "$rc" "$want_exit" "$out" | sed '2,$s/^/       /'
    fi
}

if date -d '2026-01-01T00:00:00+09:00' +%s >/dev/null 2>&1; then
    a7_case "A7 passes times in order (date-only lines and the summary ignored)" 0 'PASS A7 Event Log times are in order' \
"- 2026-10-16 — HUMAN — workspace created
- 2026-10-17T10:00:00+09:00 — ORCHESTRATOR — run-start run=demo-1
- 2026-10-17T10:05:00+09:00 — ORCHESTRATOR — stage-start stage=developer rev=1"
    a7_case "A7 catches a time that goes backwards" 1 'FAIL A7' \
"- 2026-10-17T10:00:00+09:00 — ORCHESTRATOR — run-start run=demo-1
- 2026-10-17T10:20:00+09:00 — DEVELOPER — artifact-written file=50_implementation.md rev=1
- 2026-10-17T10:10:00+09:00 — ORCHESTRATOR — stage-end stage=developer rev=1 outcome=ok"
    a7_case "A7 accepts a backwards time once a later line corrects it" 0 'PASS A7 Event Log times out of order but acknowledged' \
"- 2026-10-17T10:00:00+09:00 — ORCHESTRATOR — run-start run=demo-1
- 2026-10-17T10:20:00+09:00 — DEVELOPER — artifact-written file=50_implementation.md rev=1
- 2026-10-17T10:10:00+09:00 — ORCHESTRATOR — stage-end stage=developer rev=1 outcome=ok
- 2026-10-17T10:11:00+09:00 — ORCHESTRATOR — correction ref=2026-10-17T10:20:00+09:00 — estimated, not from date"
    a7_case "A7 catches a time in the future" 1 'FAIL A7.*in the future' \
"- 2026-10-17T10:00:00+09:00 — ORCHESTRATOR — run-start run=demo-1
- 2099-01-01T00:00:00+09:00 — DEVELOPER — artifact-written file=50_implementation.md rev=1"
else
    printf 'skip A7 (date(1) cannot parse ISO 8601)\n'
fi

# ----------------------------------------------------------- token report
#
# Models what token-report.py has to get right (design/measurement.md 5-6):
#  - one API response split across several records, each repeating the
#    same usage, is counted once;
#  - each subagent file is one stage, named by its meta.json, and rev is
#    the order of invocation, not the order of file names;
#  - cache writes are split by TTL and weighted into ieq.
# Expected ieq: stage = 1 + 10*5 + 100*0.1 + 1000*1.25 = 1311;
#               orchestration (1h cache) = 1 + 50 + 10 + 1000*2 = 2061.

TOKREPORT="$HERE/../token-report.py"
if command -v python3 >/dev/null 2>&1; then
    TESTS=$((TESTS + 1))
    sess="$TMPROOT/tok/s1"
    mkdir -p "$sess/subagents"
    u1h='"usage":{"input_tokens":1,"output_tokens":10,"cache_read_input_tokens":100,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_1h_input_tokens":1000,"ephemeral_5m_input_tokens":0}}'
    u5m='"usage":{"input_tokens":1,"output_tokens":10,"cache_read_input_tokens":100,"cache_creation_input_tokens":1000}'
    {
        printf '{"requestId":"r1","timestamp":"2026-10-01T00:00:00Z","message":{"model":"m",%s}}\n' "$u1h"
        printf '{"requestId":"r1","timestamp":"2026-10-01T00:00:00Z","message":{"model":"m",%s}}\n' "$u1h"
        printf '{"type":"user","message":{"content":"no usage here"}}\n'
    } >"$sess.jsonl"
    # agent-a sorts first by name but was invoked second.
    printf '{"requestId":"r3","timestamp":"2026-10-01T00:02:00Z","message":{"model":"m",%s}}\n' "$u5m" \
        >"$sess/subagents/agent-a.jsonl"
    printf '{"requestId":"r2","timestamp":"2026-10-01T00:01:00Z","message":{"model":"m",%s}}\n' "$u5m" \
        >"$sess/subagents/agent-b.jsonl"
    printf '{"agentType":"developer"}\n' >"$sess/subagents/agent-a.meta.json"
    printf '{"agentType":"developer"}\n' >"$sess/subagents/agent-b.meta.json"
    out=$(python3 -I "$TOKREPORT" "$sess.jsonl" --format log 2>&1 | grep '^tokens ')
    stage='model=m input=1 output=10 cacheRead=100 cacheCreation5m=1000 cacheCreation1h=0 requests=1 ieq=1311'
    want="tokens scope=stage stage=developer rev=1 $stage
tokens scope=stage stage=developer rev=2 $stage
tokens scope=orchestration model=m input=1 output=10 cacheRead=100 cacheCreation5m=0 cacheCreation1h=1000 requests=1 ieq=2061
tokens scope=run stages=2 input=3 output=30 cacheRead=300 cacheCreation5m=2000 cacheCreation1h=1000 requests=3 ieq=4683"
    if [ "$out" = "$want" ]; then
        printf 'ok   token report: one count per response, one stage per subagent, weighted ieq\n'
    else
        FAILURES=$((FAILURES + 1))
        printf 'FAIL token report: one count per response, one stage per subagent, weighted ieq\n       got:\n%s\n       want:\n%s\n' "$out" "$want"
    fi

    TESTS=$((TESTS + 1))
    out=$(python3 -I "$TOKREPORT" "$sess.jsonl" --since 2026-10-01T00:01:30Z --format log 2>&1)
    if printf '%s' "$out" | grep -q '^tokens scope=run stages=1 .* requests=1 ieq=1311$'; then
        printf 'ok   token report honours --since\n'
    else
        FAILURES=$((FAILURES + 1))
        printf 'FAIL token report honours --since\n       got:\n%s\n' "$out"
    fi

    # T-14: each stage's model against its definition's `model:`. The
    # fixture's model is a real-looking id so the alias rule is exercised:
    # `sonnet` must match claude-sonnet-*, and must not match claude-opus-*.
    TESTS=$((TESTS + 1))
    msess="$TMPROOT/tok/s2"
    agents="$TMPROOT/tok/agents"
    mkdir -p "$msess/subagents" "$agents"
    printf '{"requestId":"m1","timestamp":"2026-10-01T00:00:00Z","message":{"model":"claude-opus-9-9",%s}}\n' "$u1h" >"$msess.jsonl"
    printf '{"requestId":"m2","timestamp":"2026-10-01T00:01:00Z","message":{"model":"claude-sonnet-9-9",%s}}\n' "$u5m" \
        >"$msess/subagents/agent-a.jsonl"
    printf '{"requestId":"m3","timestamp":"2026-10-01T00:02:00Z","message":{"model":"claude-sonnet-9-9",%s}}\n' "$u5m" \
        >"$msess/subagents/agent-b.jsonl"
    printf '{"requestId":"m4","timestamp":"2026-10-01T00:03:00Z","message":{"model":"claude-sonnet-9-9",%s}}\n' "$u5m" \
        >"$msess/subagents/agent-c.jsonl"
    printf '{"agentType":"developer"}\n' >"$msess/subagents/agent-a.meta.json"
    printf '{"agentType":"quality-assurance"}\n' >"$msess/subagents/agent-b.meta.json"
    printf '{"agentType":"designer"}\n' >"$msess/subagents/agent-c.meta.json"
    printf -- '---\nname: developer\nmodel: sonnet\n---\n' >"$agents/developer.md"
    printf -- '---\nname: quality-assurance\nmodel: opus\n---\n' >"$agents/quality-assurance.md"
    printf -- '---\nname: designer\nmodel: inherit\n---\n' >"$agents/designer.md"
    out=$(python3 -I "$TOKREPORT" "$msess.jsonl" --format log --agents-dir "$agents" 2>"$TMPROOT/tok/err" | grep '^model-check ')
    want="model-check scope=stage stage=developer rev=1 expected=sonnet actual=claude-sonnet-9-9 result=match
model-check scope=stage stage=quality-assurance rev=1 expected=opus actual=claude-sonnet-9-9 result=mismatch
model-check scope=stage stage=designer rev=1 expected=inherit actual=claude-sonnet-9-9 result=unspecified
model-check scope=orchestration models=claude-opus-9-9 result=single
model-check scope=run stages=3 mismatches=1 result=mismatch"
    if [ "$out" = "$want" ] && grep -q 'model mismatch: quality-assurance rev=1' "$TMPROOT/tok/err"; then
        printf 'ok   token report: model check against each definition, mismatch warned\n'
    else
        FAILURES=$((FAILURES + 1))
        printf 'FAIL token report: model check against each definition, mismatch warned\n       got:\n%s\n       want:\n%s\n' "$out" "$want"
    fi

    # A model switched mid-session shows up on the orchestration line.
    TESTS=$((TESTS + 1))
    printf '{"requestId":"m5","timestamp":"2026-10-01T00:04:00Z","message":{"model":"claude-sonnet-9-9",%s}}\n' "$u1h" >>"$msess.jsonl"
    out=$(python3 -I "$TOKREPORT" "$msess.jsonl" --format log --agents-dir "$agents" 2>/dev/null)
    if printf '%s' "$out" | grep -q '^model-check scope=orchestration models=.*+.* result=switched$'; then
        printf 'ok   token report: a mid-run model switch in the main session is reported\n'
    else
        FAILURES=$((FAILURES + 1))
        printf 'FAIL token report: a mid-run model switch in the main session is reported\n       got:\n%s\n' "$out"
    fi
else
    printf 'skip token report (python3 not installed)\n'
fi

# --------------------------------------------------------- static checks

TESTS=$((TESTS + 1))
if bash -n "$VERIFY" && bash -n "$HERE/run-tests.sh"; then
    printf 'ok   both scripts parse\n'
else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL both scripts parse\n'
fi

if command -v shellcheck >/dev/null 2>&1; then
    TESTS=$((TESTS + 1))
    if shellcheck -S warning "$VERIFY"; then
        printf 'ok   shellcheck clean\n'
    else
        FAILURES=$((FAILURES + 1))
        printf 'FAIL shellcheck clean\n'
    fi
fi

# ------------------------------------------------- documentation coherence

REPO_ROOT=$(cd "$HERE/../.." && pwd)

assert_docs() {
    # assert_docs <name> <0-if-should-match> <literal-string> [file-to-ignore]
    # Matching files are listed and then filtered, rather than leaning on
    # grep's --exclude, whose interaction with --include is order-dependent
    # enough to have already produced one false result here.
    local name="$1" want="$2" needle="$3" ignore="${4:-}"
    local hits found
    TESTS=$((TESTS + 1))
    hits=$(grep -rl --include='*.md' -F "$needle" "$REPO_ROOT" 2>/dev/null)
    if [ -n "$ignore" ]; then
        hits=$(printf '%s\n' "$hits" | grep -v "/$ignore\$")
    fi
    hits=$(printf '%s\n' "$hits" | sed '/^$/d')
    if [ -n "$hits" ]; then found=0; else found=1; fi
    if [ "$found" -eq "$want" ]; then
        printf 'ok   %s\n' "$name"
    else
        FAILURES=$((FAILURES + 1))
        printf 'FAIL %s (matched: %s)\n' "$name" "$(printf '%s' "$hits" | tr '\n' ' ')"
    fi
}

# CHANGELOG.md is exempt: recording the corrected wording is what a
# changelog is for. Everywhere else, the claim is simply false.
assert_docs "no live doc still claims there is no 70 in the main line" 1 \
    "there is no \`70\` in the main line" CHANGELOG.md
assert_docs "the design approval artifact is documented" 0 "45_design_approval.md"
assert_docs "the mock build artifact is documented" 0 "44_mock_build.md"
assert_docs "the ledger is documented" 0 "docs/OPEN-DECISIONS.md"
assert_docs "the token report is documented" 0 "token-report.py"

# The failure-tag vocabulary is defined in the QA agent and summed in the
# STATUS template; a tag renamed in one place and not the other would make
# the counts silently stop adding up.
TESTS=$((TESTS + 1))
missing=""
for tag in spec misalignment verification impl-bug; do
    grep -qF "\`$tag\`" "$REPO_ROOT/agents/quality-assurance.md" || missing="$missing qa:$tag"
    grep -qF "$tag=" "$REPO_ROOT/templates/STATUS.md" || missing="$missing status:$tag"
done
if [ -z "$missing" ]; then
    printf 'ok   failure tags agree between the QA agent and the STATUS template\n'
else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL failure tags agree between the QA agent and the STATUS template (missing:%s)\n' "$missing"
fi

TESTS=$((TESTS + 1))
hooked=$(grep -l 'block-git-write.sh' "$REPO_ROOT"/agents/*.md | wc -l | tr -d ' ')
bashed=$(grep -l '^tools:.*Bash' "$REPO_ROOT"/agents/*.md | wc -l | tr -d ' ')
if [ "$hooked" = "$bashed" ]; then
    printf 'ok   every Bash-capable agent carries the git-write hook (%s)\n' "$hooked"
else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL every Bash-capable agent carries the git-write hook (%s hooked, %s with Bash)\n' "$hooked" "$bashed"
fi

# ---------------------------------------------------------------- summary

printf '\n%d tests, %d failures\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
