#!/bin/bash
# block-git-write.sh
#
# PreToolUse hook (matcher: Bash) used by Claude Dev Team agents that have
# Bash access (Project Manager, Solution Architect, Developer, Quality
# Assurance, Process Advisor).
#
# Purpose: structural enforcement of the harness's #1 hard rule -- agents
# never run git commands that mutate repository or remote state. Humans
# commit, push, merge, rebase, and tag; agents prepare diffs, branches, and
# commit-message text for a human to run.
#
# This is defense-in-depth, not the primary control. The primary control
# should be a permissions.deny rule in the consuming project's
# .claude/settings.json (see README.md, "Recommended settings.json
# additions"). Add this hook in addition to that rule, not instead of it --
# a hook only covers agents that reference it in their own frontmatter,
# while a permissions.deny rule applies session-wide.
#
# Exit code 2 blocks the tool call and returns stderr to the agent as the
# reason (see https://code.claude.com/docs/en/hooks for the exit-code
# contract). Any other exit code allows the command through.
#
# This is a heuristic pattern match on the command string, not a full shell
# parser. It will not catch every way to smuggle a mutating git command past
# it (e.g. wrapping it in a script, an alias, or a language runtime's
# subprocess call), and it may occasionally block a legitimate read-only
# command that merely contains one of these words in an argument or path.
# Treat it as a tripwire, not a guarantee -- combine it with the
# settings.json permission rule and with normal human review of anything an
# agent asks you to run.

set -u

INPUT=$(cat)

# jq is assumed present (Claude Code ships it for hook use in its own docs
# examples). If it's missing, fail open with a warning rather than blocking
# every Bash call in a project that lacks jq.
if ! command -v jq >/dev/null 2>&1; then
  echo "block-git-write.sh: jq not found on PATH; skipping git-write check for this call." >&2
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only inspect commands that actually invoke git (as a bare word, so we don't
# false-positive on e.g. "cat legit-file.md" or a path containing "git").
if ! printf '%s' "$COMMAND" | grep -qE '(^|[;&|]|[[:space:]])git([[:space:]]|$)'; then
  exit 0
fi

# git subcommands that mutate local history, the working tree, refs, or the
# remote. Read-only / staging / inspection subcommands (status, diff, log,
# show, add, branch <name> without -D, switch -c, stash) are intentionally
# left alone -- those are how an agent prepares a change for a human to
# review and commit, and blocking them would defeat the harness's own
# "prepare diffs/branches" workflow.
BLOCKED_SUBCOMMANDS='\b(commit|push|merge|rebase|reset|cherry-pick|revert|filter-branch|filter-repo|clean|gc|prune|update-ref|symbolic-ref)\b'

# Force / destructive flags that turn an otherwise-safe subcommand dangerous
# (e.g. `git branch -D`, `git checkout -f`, `git tag -f`, `git push --force`).
FORCE_FLAGS='(--force([[:space:]=]|$)|--force-with-lease|--hard\b|[[:space:]]-D\b|[[:space:]]-f\b)'

if printf '%s' "$COMMAND" | grep -qE "$BLOCKED_SUBCOMMANDS"; then
  echo "BLOCKED by claude-dev-team/block-git-write.sh: '$COMMAND' looks like a git command that mutates repository or remote state (commit/push/merge/rebase/reset/etc). Claude Dev Team agents must never run this. Prepare the change (diff, branch, suggested commit message) in the pipeline artifact instead, and ask the human operator to run the git command themselves." >&2
  exit 2
fi

if printf '%s' "$COMMAND" | grep -qE "$FORCE_FLAGS"; then
  echo "BLOCKED by claude-dev-team/block-git-write.sh: '$COMMAND' uses a force/destructive flag. A human must review and run this manually." >&2
  exit 2
fi

exit 0
