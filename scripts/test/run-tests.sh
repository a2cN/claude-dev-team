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
