#!/usr/bin/env bash
#
# verify-dev-team.sh — check that a Claude Dev Team run left the record it
# was supposed to leave.
#
# This is NOT a Claude Code hook. `hooks/block-git-write.sh` matches a
# command string at tool-call time; this reads the filesystem and `git
# diff` at review time. Different shape, different install location, no
# shared code.
#
# What it is for
# --------------
# The pipeline workspace is gitignored by policy, so everything that must
# survive a merge leaves it by an explicit act at completion: promotion
# into docs/adr/ and docs/design/, and a verbatim archive into
# docs/archive/<YYYY-MM-DD>-<task-slug>/. That step had a precise,
# checkable form and no mechanism, and on its first real run it was
# skipped entirely — the change would have merged with its whole audit
# trail discarded. Per DOCUMENT-POLICY.md: "A rule with a mechanical form
# and no mechanism is a rule you have decided to violate later."
#
# Honest limit
# ------------
# Because the workspace is gitignored, CI cannot see a run in flight. This
# script asks the PR to declare which runs it carries (`Dev-Team-Run:`)
# rather than discovering them. That is a self-report: it cannot catch a
# pipeline run that left no trace at all. What it does catch is the case
# that actually happened — a run that produced artifacts and then dropped
# them — and it turns an omission from silence into a line a reviewer can
# see.
#
# Usage
#   verify-dev-team.sh [--slug <slug>]... [--base <ref>] [--quiet] [--strict]
#   verify-dev-team.sh --workspace <dir>
#   verify-dev-team.sh --help
#
# Exit codes
#   0  all checks passed (or were legitimately skipped)
#   1  at least one check failed
#   2  usage error, or the environment cannot support the checks
#
set -u

PROG=${0##*/}

SLUGS=""
BASE=""
QUIET=0
STRICT=0
WORKSPACE=""

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Placeholder tokens that must never survive into a committed artifact.
# Deliberately a CLOSED list of exact strings rather than a general
# `<...>` pattern: real documents contain angle brackets (HTML, generics,
# shell redirection in a pasted quality-gate log), and a checker that
# cries wolf on those gets switched off within a week.
PLACEHOLDERS='<task-slug>
<title>
<YYYY-MM-DD>
<NNN>
<path>
<slug>
<why>
<name>
<name / email>
<log entries>
<...>'

usage() {
    sed -n '3,44p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'
}

report() {
    # report <PASS|FAIL|SKIP> <check-id> <message>
    local level="$1" id="$2" msg="$3"
    case "$level" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    esac
    if [ "$level" = FAIL ]; then
        printf 'FAIL %s %s\n' "$id" "$msg"
        if [ -n "${GITHUB_ACTIONS:-}" ]; then
            printf '::error title=%s::%s\n' "$id" "$msg"
        fi
    elif [ "$QUIET" -eq 0 ]; then
        printf '%s %s %s\n' "$level" "$id" "$msg"
    fi
}

die() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

trim() {
    # strip leading and trailing whitespace from $1
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# ---------------------------------------------------------------- parsing

while [ $# -gt 0 ]; do
    case "$1" in
        --slug)
            [ $# -ge 2 ] || die "--slug needs a value"
            SLUGS="$SLUGS
$2"
            shift 2
            ;;
        --base)
            [ $# -ge 2 ] || die "--base needs a value"
            BASE="$2"
            shift 2
            ;;
        --workspace)
            [ $# -ge 2 ] || die "--workspace needs a value"
            WORKSPACE="$2"
            shift 2
            ;;
        --quiet) QUIET=1; shift ;;
        --strict) STRICT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
done

# ------------------------------------------------------- placeholder scan

scan_placeholders() {
    # scan_placeholders <check-id> <file>...
    # Reports one FAIL per offending file. Fenced code blocks and HTML
    # comments are exempt: a template's instructions live in comments, and
    # a pasted terminal log is not a document with a blank in it.
    local id="$1"; shift
    local file found
    for file in "$@"; do
        [ -f "$file" ] || continue
        found=$(PLACEHOLDERS="$PLACEHOLDERS" awk '
            BEGIN {
                n = split(ENVIRON["PLACEHOLDERS"], p, "\n")
            }
            /^[[:space:]]*```/ { fence = !fence; next }
            fence { next }
            {
                line = $0
                if (incomment) {
                    if (index(line, "-->")) {
                        incomment = 0
                        line = substr(line, index(line, "-->") + 3)
                    } else next
                }
                while ((s = index(line, "<!--")) > 0) {
                    rest = substr(line, s + 4)
                    line = substr(line, 1, s - 1)
                    if ((e = index(rest, "-->")) > 0) {
                        line = line substr(rest, e + 3)
                    } else {
                        incomment = 1
                        break
                    }
                }
                for (i = 1; i <= n; i++) {
                    if (p[i] != "" && index(line, p[i])) {
                        print FILENAME ":" FNR ": " p[i]
                        next
                    }
                }
            }
        ' "$file")
        if [ -n "$found" ]; then
            report FAIL "$id" "unfilled placeholder in a committed artifact: $(printf '%s' "$found" | head -n1)"
        fi
    done
}

# ------------------------------------------------------- ledger machinery

LEDGER="docs/OPEN-DECISIONS.md"

ledger_row_ids() {
    [ -f "$LEDGER" ] || return 0
    awk -F'|' '
        /^[[:space:]]*\|/ {
            id = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
            if (id ~ /^OD-[A-Za-z0-9._-]+-[0-9][0-9]$/) print id
        }
    ' "$LEDGER"
}

cited_ids() {
    # Every OD- id referenced anywhere the ledger itself is not.
    local paths=""
    [ -d docs/archive ] && paths="$paths docs/archive"
    [ -d docs/design ] && paths="$paths docs/design"
    [ -d docs/adr ] && paths="$paths docs/adr"
    [ -n "$paths" ] || return 0
    # shellcheck disable=SC2086
    grep -rhoE 'OD-[A-Za-z0-9._-]+-[0-9][0-9]' $paths 2>/dev/null | sort -u
}

check_ledger() {
    local cited row_ids missing dup
    cited=$(cited_ids)
    row_ids=$(ledger_row_ids)

    if [ ! -f "$LEDGER" ]; then
        if [ -n "$cited" ]; then
            report FAIL C1 "$LEDGER is missing, but these OD- ids are cited in docs/: $(printf '%s' "$cited" | tr '\n' ' ')"
        else
            report SKIP C1 "$LEDGER not present and no OD- ids cited; project has not adopted the ledger"
        fi
        return
    fi
    report PASS C1 "$LEDGER present"

    missing=""
    local id
    for id in $cited; do
        if ! printf '%s\n' "$row_ids" | grep -qxF "$id"; then
            missing="$missing $id"
        fi
    done
    if [ -n "$missing" ]; then
        report FAIL C2 "cited but absent from the ledger:$missing"
    else
        report PASS C2 "every cited OD- id resolves to a ledger row"
    fi

    dup=$(printf '%s\n' "$row_ids" | sed '/^$/d' | sort | uniq -d)
    if [ -n "$dup" ]; then
        report FAIL C3 "duplicate ledger ids: $(printf '%s' "$dup" | tr '\n' ' ')"
    else
        report PASS C3 "ledger ids are unique"
    fi
}

check_ledger_append_only() {
    local base_ids gone id
    if [ -z "$BASE" ]; then
        report SKIP C4 "no base ref resolved; cannot check the ledger is append-only"
        return
    fi
    if ! git cat-file -e "$BASE:$LEDGER" 2>/dev/null; then
        report SKIP C4 "$LEDGER does not exist at $BASE; nothing to compare"
        return
    fi
    base_ids=$(git show "$BASE:$LEDGER" | awk -F'|' '
        /^[[:space:]]*\|/ {
            id = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
            if (id ~ /^OD-[A-Za-z0-9._-]+-[0-9][0-9]$/) print id
        }')
    gone=""
    for id in $base_ids; do
        if ! ledger_row_ids | grep -qxF "$id"; then
            gone="$gone $id"
        fi
    done
    if [ -n "$gone" ]; then
        report FAIL C4 "ledger rows deleted since $BASE (append-only; only a human closes, nobody deletes):$gone"
    else
        report PASS C4 "ledger is append-only against $BASE"
    fi
}

# ------------------------------------------------------- workspace preflight

if [ -n "$WORKSPACE" ]; then
    [ -d "$WORKSPACE" ] || die "no such workspace directory: $WORKSPACE"
    # Deliberately NOT checking for PENDING_HUMAN_APPROVAL here: in a live
    # workspace an unsigned gate is the correct state. That check applies
    # to the archive, where a blank means the snapshot was taken too early.
    scan_placeholders A5 "$WORKSPACE"/*.md
    [ "$FAIL_COUNT" -eq 0 ] && report PASS A5 "no unfilled placeholders in $WORKSPACE"
    check_ledger
    printf '\n%d passed, %d failed, %d skipped\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
    [ "$FAIL_COUNT" -gt 0 ] && exit 1
    exit 0
fi

# ------------------------------------------------------------ repo mode

git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repository (use --workspace for a bare workspace check)"
cd "$(git rev-parse --show-toplevel)" || die "cannot cd to repository root"

if [ -z "$BASE" ]; then
    if [ -n "${GITHUB_BASE_REF:-}" ] && git rev-parse --verify --quiet "origin/$GITHUB_BASE_REF" >/dev/null; then
        BASE="origin/$GITHUB_BASE_REF"
    elif git rev-parse --verify --quiet origin/main >/dev/null; then
        BASE="origin/main"
    elif git rev-parse --verify --quiet main >/dev/null; then
        BASE="main"
    else
        BASE=""
    fi
elif ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
    die "base ref does not exist: $BASE"
fi

changed_files() {
    if [ -n "$BASE" ]; then
        git diff --name-only "$BASE...HEAD"
    else
        git ls-files
    fi
}

# ---- slug discovery, in priority order

declared_none=0

if [ -z "$(trim "$SLUGS")" ] && [ -n "${PR_BODY:-}" ]; then
    # PR_BODY is untrusted external text. It is read from the environment
    # and piped, never interpolated into a command line.
    decl=$(printf '%s\n' "$PR_BODY" | grep -iE '^[[:space:]]*Dev-Team-Run:' | head -n1)
    if [ -n "$decl" ]; then
        decl=${decl#*:}
        if printf '%s' "$decl" | grep -qiE '^[[:space:]]*none[[:space:]]*$'; then
            declared_none=1
        else
            SLUGS=$(printf '%s' "$decl" | tr ',' '\n' | sed 's/[^A-Za-z0-9._-]//g' | sed '/^$/d')
        fi
    fi
fi

if [ -z "$(trim "$SLUGS")" ] && [ "$declared_none" -eq 0 ]; then
    SLUGS=$(changed_files \
        | sed -n 's|^\(docs/archive/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-[^/]*\)/.*|\1|p' \
        | sed 's|^docs/archive/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-||' \
        | sort -u)
fi

SLUGS=$(printf '%s\n' "$SLUGS" | sed '/^$/d')

if [ -z "$SLUGS" ] && [ "$declared_none" -eq 0 ]; then
    if changed_files | grep -qv '^docs/'; then
        report FAIL A0 "this change touches code but declares no pipeline run. Add 'Dev-Team-Run: <task-slug>' to the PR body, or 'Dev-Team-Run: none' if this change did not come from the pipeline."
    else
        report SKIP A0 "docs-only change with no declared run"
    fi
else
    if [ "$declared_none" -eq 1 ]; then
        report SKIP A0 "PR declares Dev-Team-Run: none"
    else
        report PASS A0 "runs declared: $(printf '%s' "$SLUGS" | tr '\n' ' ')"
    fi
fi

# ---- A1 / A2 / B1 / B2, per declared slug

archive_dir_for() {
    find docs/archive -maxdepth 1 -type d -name "????-??-??-$1" 2>/dev/null | sort
}

plan_stage_required() {
    # plan_stage_required <plan-file> <stage-label> -> "required" | "na" | "unknown"
    local plan="$1" label="$2" line value
    [ -f "$plan" ] || { printf 'unknown'; return; }
    line=$(grep -iE "^[[:space:]]*[-*][[:space:]]*$label:" "$plan" | head -n1)
    [ -n "$line" ] || { printf 'unknown'; return; }
    value=$(printf '%s' "${line#*:}" | tr '[:upper:]' '[:lower:]')
    case "$(trim "$value")" in
        required*) printf 'required' ;;
        n/a*|na*|not*) printf 'na' ;;
        *) printf 'unknown' ;;
    esac
}

check_promotion_table() {
    # check_promotion_table <90_completion.md> <slug>
    local file="$1" slug="$2" pendings dests d
    if [ ! -f "$file" ]; then
        report FAIL B1 "$slug: 90_completion.md missing from the archive; nothing records what was due for promotion"
        return
    fi
    # The archive row is expected to stay `pending`: the Developer cannot
    # mark it done inside the copy that marking would have to precede. Its
    # truth is A1, not this cell.
    pendings=$(awk -F'|' '
        /^[[:space:]]*\|/ {
            src = $2; dest = $3; status = $5
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", src)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", dest)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
            if (src ~ /^[-: ]*$/) next
            if (tolower(src) ~ /source/) next
            if (tolower(src) ~ /entire workspace/) next
            if (dest ~ /docs\/archive/) next
            if (tolower(status) ~ /pending/) print src
        }
    ' "$file")
    if [ -n "$pendings" ]; then
        report FAIL B1 "$slug: promotion never ran for: $(printf '%s' "$pendings" | tr '\n' ';')"
    else
        report PASS B1 "$slug: every promotion row is done or N/A"
    fi

    dests=$(awk -F'|' '
        /^[[:space:]]*\|/ {
            dest = $3; status = $5
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", dest)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
            if (tolower(status) ~ /done/ && dest !~ /docs\/archive/ && dest ~ /^docs\//) print dest
        }
    ' "$file")
    local missing=""
    for d in $dests; do
        [ -e "$d" ] || missing="$missing $d"
    done
    if [ -n "$missing" ]; then
        report FAIL B2 "$slug: promotion marked done but the destination does not exist:$missing"
    elif [ -n "$dests" ]; then
        report PASS B2 "$slug: every promoted destination exists"
    else
        report SKIP B2 "$slug: no promotion destinations marked done"
    fi
}

for slug in $SLUGS; do
    dirs=$(archive_dir_for "$slug")
    count=$(printf '%s\n' "$dirs" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        report FAIL A1 "$slug: no docs/archive/<YYYY-MM-DD>-$slug/ in this change. The workspace is gitignored, so the run's inputs are destroyed at merge."
        continue
    elif [ "$count" -gt 1 ]; then
        report FAIL A1 "$slug: more than one archive directory: $(printf '%s' "$dirs" | tr '\n' ' ')"
        continue
    fi
    report PASS A1 "$slug: archived at $dirs"

    adir="$dirs"

    required="00_request.md 10_product_brief.md 20_project_plan.md STATUS.md 50_implementation.md 60_qa_report.md 90_completion.md"
    plan="$adir/20_project_plan.md"
    case "$(plan_stage_required "$plan" 'architecture')" in
        required) required="$required 30_architecture.md" ;;
    esac
    case "$(plan_stage_required "$plan" 'design')" in
        required) required="$required 40_design_brief.md" ;;
    esac
    case "$(plan_stage_required "$plan" 'design approval')" in
        required) required="$required 45_design_approval.md" ;;
        unknown)
            report FAIL A2 "$slug: 20_project_plan.md has no readable 'Design approval:' line. The Developer's gate quotes that line; without it a missing approval sheet is indistinguishable from one that was never needed."
            ;;
    esac
    absent=""
    for f in $required; do
        [ -f "$adir/$f" ] || absent="$absent $f"
    done
    if [ -n "$absent" ]; then
        report FAIL A2 "$slug: archived run is missing:$absent"
    else
        report PASS A2 "$slug: every artifact the plan required is archived"
    fi

    # A4 — the gates the archive claims were passed
    for gate in 20_project_plan.md 45_design_approval.md 90_completion.md; do
        [ -f "$adir/$gate" ] || continue
        if grep -q 'Approval Status:.*APPROVED' "$adir/$gate"; then
            report PASS A4 "$slug: $gate is signed"
        else
            report FAIL A4 "$slug: $gate was archived without an APPROVED gate"
        fi
    done

    check_promotion_table "$adir/90_completion.md" "$slug"
done

# ---- A3 / A5 / A6 — archive invariants, whatever the declared slugs

if [ -d docs/archive ]; then
    unsigned=$(grep -rl 'PENDING_HUMAN_APPROVAL' docs/archive 2>/dev/null)
    if [ -n "$unsigned" ]; then
        report FAIL A3 "archived files still carry an unsigned approval field (the snapshot was taken before the human signed): $(printf '%s' "$unsigned" | tr '\n' ' ')"
    else
        report PASS A3 "no archived file is waiting for a signature"
    fi

    before=$FAIL_COUNT
    # shellcheck disable=SC2044
    for f in $(find docs/archive -name '*.md' -type f 2>/dev/null); do
        scan_placeholders A5 "$f"
    done
    [ "$FAIL_COUNT" -eq "$before" ] && report PASS A5 "no unfilled placeholders under docs/archive/"

    if [ -n "$BASE" ]; then
        touched=$(git diff --name-status "$BASE...HEAD" -- docs/archive/ | grep -vE '^A' || true)
        if [ -n "$touched" ]; then
            report FAIL A6 "an archived file was modified or deleted; the archive is immutable once written: $(printf '%s' "$touched" | tr '\n' ' ')"
        else
            report PASS A6 "docs/archive/ is append-only against $BASE"
        fi
    else
        report SKIP A6 "no base ref resolved; cannot check archive immutability"
    fi
else
    report SKIP A3 "no docs/archive/ yet"
fi

# ---- B3 — a design canon directory has a README

if [ -d docs/design ]; then
    missing=""
    for d in docs/design/*/; do
        [ -d "$d" ] || continue
        [ -f "$d/README.md" ] || missing="$missing $d"
    done
    if [ -n "$missing" ]; then
        report FAIL B3 "design canon with no README.md (the promoted 45_design_approval.md — a brief alone is a proposal, not canon):$missing"
    else
        report PASS B3 "every docs/design/<slug>/ has a README.md"
    fi
fi

# ---- C — the ledger

check_ledger
check_ledger_append_only

# ---------------------------------------------------------------- summary

printf '\n%d passed, %d failed, %d skipped\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
if [ "$STRICT" -eq 1 ] && [ "$SKIP_COUNT" -gt 0 ]; then
    printf '%s: --strict, and %d checks were skipped\n' "$PROG" "$SKIP_COUNT" >&2
    exit 1
fi
exit 0
