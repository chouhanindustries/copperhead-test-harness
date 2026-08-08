#!/usr/bin/env bash
#
# One `copperhead create` attempt, fully captured.
#
# Everything an attempt produces lands in its own directory under run-logs/,
# outside the design workspace — a rollback's `git clean -fd` cannot reach it,
# and the design agent's `search` never sees it.
#
# Attempts are grouped by SESSION — one session per brief. Every rerun against
# the same workspace and the same brief lands in the same session directory,
# named for when that campaign started, so the whole history of driving one
# brief to green reads top to bottom in one place. A different brief (or a
# different workspace) starts a new session.
#
#   run-logs/<session>/          e.g. 2026-07-31T23-32-26
#     session.json               brief identity, workspace, attempt index
#     attempt-NN/
#       metadata.json            machine-readable record of that attempt
#       create.log               full terminal capture, stdout+stderr
#       REPORT.md                the human attempt report (guide §6)
#       evidence/                run transcripts + repo state, copied at exit
#       outputs/                 what the pipeline produced that attempt
#
# Usage:
#   run-attempt.sh [options] "<the one variable changed vs the previous attempt>"
#
#   -w, --workspace DIR   design workspace to run in   (default: $PWD when it holds
#                         the brief; otherwise required)
#   -b, --brief FILE      brief, relative to the workspace   (default: brief.md)
#   -s, --src DIR         copperhead source under test   (default: <harness>/../copperhead)
#   -m, --model MODEL     model passed to `copperhead create`   (default: claude-code)
#   -o, --run-logs DIR    where sessions are written   (default: <harness>/run-logs)
#   -h, --help            this text
#
# Runnable from anywhere — the harness locates itself, and every path it writes
# is absolute. Workspaces normally live under <harness>/workspaces, but point
# --workspace anywhere to drive a different brief with the same harness: its
# attempts land in their own session (sessions are keyed on workspace + brief).
#
# Equivalent environment variables, for callers that would rather not pass
# flags: COPPERHEAD_WORKSPACE, COPPERHEAD_BRIEF, COPPERHEAD_SRC,
# COPPERHEAD_MODEL, COPPERHEAD_RUNLOGS. A flag beats the variable.
#
# Run logs default to <harness>/run-logs, which the distributed repo does not
# track. Point --run-logs somewhere outside the clone if you would rather keep
# a campaign's history entirely separate from the harness checkout.
#
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; }

WORKSPACE="${COPPERHEAD_WORKSPACE:-}"
BRIEF="${COPPERHEAD_BRIEF:-brief.md}"
SRC="${COPPERHEAD_SRC:-}"
MODEL="${COPPERHEAD_MODEL:-claude-code}"
RUNLOGS="${COPPERHEAD_RUNLOGS:-$HARNESS/run-logs}"
VARIABLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -w|--workspace) WORKSPACE="$2"; shift 2 ;;
    -b|--brief)     BRIEF="$2";     shift 2 ;;
    -s|--src)       SRC="$2";       shift 2 ;;
    -m|--model)     MODEL="$2";     shift 2 ;;
    -o|--run-logs)  RUNLOGS="$2";   shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    -*)             echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)              VARIABLE="$1";  shift ;;
  esac
done
VARIABLE="${VARIABLE:-none — baseline}"

# Workspace default: the current directory when it looks like one (it holds the
# brief). Running `run-attempt.sh` from inside a workspace should just work.
# Anything else is a guess, and a guess here runs a multi-hour attempt against
# the wrong board — so refuse and say what is available instead.
if [ -z "$WORKSPACE" ]; then
  if [ -f "$PWD/$BRIEF" ]; then
    WORKSPACE="$PWD"
  else
    echo "no workspace: $PWD holds no $BRIEF, and none was given with -w" >&2
    if [ -d "$HARNESS/workspaces" ]; then
      echo "available under $HARNESS/workspaces:" >&2
      for w in "$HARNESS"/workspaces/*/; do [ -d "$w" ] && echo "  $(basename "$w")" >&2; done
    fi
    echo "create one with: $HARNESS/bin/new-workspace.sh <brief>" >&2
    exit 2
  fi
fi
WORKSPACE="$(cd "$WORKSPACE" 2>/dev/null && pwd)" || { echo "no workspace at $WORKSPACE" >&2; exit 2; }
SRC="${SRC:-$HARNESS/../copperhead}"
SRC="$(cd "$SRC" 2>/dev/null && pwd)" || { echo "no copperhead source at $SRC" >&2; exit 2; }
mkdir -p "$RUNLOGS" || { echo "cannot create run-logs at $RUNLOGS" >&2; exit 2; }
RUNLOGS="$(cd "$RUNLOGS" && pwd)"

cd "$WORKSPACE" || { echo "no workspace at $WORKSPACE" >&2; exit 2; }

# Resolve the session: same workspace + same brief content -> same directory.
# Keyed on the brief's hash rather than its path, because editing the brief
# changes what is being tested and should not fold into the previous campaign's
# history.
[ -f "$BRIEF" ] || { echo "no brief at $WORKSPACE/$BRIEF" >&2; exit 2; }
BRIEF_SHA="$(sha256sum "$BRIEF" | cut -c1-16)"
SESSION=""
for s in "$RUNLOGS"/*/session.json; do
  [ -f "$s" ] || continue
  if [ "$(node -e 'const s=require(process.argv[1]);process.stdout.write(s.brief?.sha===process.argv[2]&&s.workspace===process.argv[3]?"1":"")' "$s" "$BRIEF_SHA" "$WORKSPACE" 2>/dev/null)" = "1" ]; then
    SESSION="$(dirname "$s")"
    break
  fi
done
if [ -z "$SESSION" ]; then
  SESSION="$RUNLOGS/$(date +%Y-%m-%dT%H-%M-%S)"
  mkdir -p "$SESSION"
fi

# Next attempt within the session, never reusing one that exists.
N=1
while [ -d "$SESSION/attempt-$(printf '%02d' $N)" ]; do N=$((N + 1)); done
N=$(printf '%02d' $N)
RUN="$SESSION/attempt-$N"
mkdir -p "$RUN/evidence" "$RUN/outputs"
LOG="$RUN/create.log"

# ---------------------------------------------------------------- preconditions
CH_BIN="$(readlink -f "$(command -v copperhead)" 2>/dev/null || echo MISSING)"
CH_VERSION="$(copperhead --version 2>/dev/null || echo MISSING)"
CH_HEAD="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo '?')"
CH_DIRTY="$(git -C "$SRC" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
CH_BRANCH="$(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
WS_HEAD_BEFORE="$(git rev-parse --short HEAD)"
NODE_V="$(node -v)"
KICAD_V="$(kicad-cli --version 2>&1 | head -1)"
DISK_BEFORE="$(df -h . | tail -1 | awk '{print $4}')"
TMP_BEFORE="$(ls -d /tmp/copperhead-* 2>/dev/null | wc -l | tr -d ' ')"
STARTED="$(date -Is)"
START_S="$(date +%s)"

# A non-executable dist/cli.js resolves to nothing and the run silently uses
# some other copperhead, or none. Refuse rather than produce a mystery result.
if [ "$CH_BIN" = MISSING ] || [ "$CH_VERSION" = MISSING ]; then
  echo "copperhead does not resolve — run 'npm run build && npm link' in $SRC" >&2
  exit 2
fi

{
  echo "=== attempt $N  $STARTED ==="
  echo "cmd:         copperhead create --brief $BRIEF --model $MODEL"
  echo "copperhead:  $CH_BIN ($CH_VERSION)"
  echo "source:      $CH_BRANCH @ $CH_HEAD (dirty: $CH_DIRTY files)"
  echo "workspace:   $WORKSPACE @ $WS_HEAD_BEFORE"
  echo "toolchain:   node $NODE_V · kicad-cli $KICAD_V"
  echo "disk:        $DISK_BEFORE free · /tmp/copperhead-*: $TMP_BEFORE"
  echo "variable:    $VARIABLE"
  echo "=== run start ==="
} | tee "$LOG"

copperhead create --brief "$BRIEF" --model "$MODEL" 2>&1 | tee -a "$LOG"
EXIT=${PIPESTATUS[0]}

ENDED="$(date -Is)"
ELAPSED=$(( $(date +%s) - START_S ))
echo "=== run end $ENDED · exit=$EXIT ===" | tee -a "$LOG"

# ---------------------------------------------------------------- evidence
# Copied before anything else touches the tree: a rerun or rebuild destroys it.
for d in .copperhead/runs/*/; do [ -d "$d" ] && cp -r "$d" "$RUN/evidence/" 2>/dev/null; done
cp .copperhead/runs/REPORT.md .copperhead/runs/report.json "$RUN/evidence/" 2>/dev/null
git status --porcelain > "$RUN/evidence/git-status.txt"
git stash list         > "$RUN/evidence/git-stash.txt"
git log --oneline -30  > "$RUN/evidence/git-log.txt"
git diff --stat "$WS_HEAD_BEFORE"..HEAD > "$RUN/evidence/git-diff-stat.txt" 2>/dev/null
df -h .                > "$RUN/evidence/disk.txt"
ls -d /tmp/copperhead-* 2>/dev/null > "$RUN/evidence/tmpdirs.txt"

# ---------------------------------------------------------------- outputs
# What the pipeline produced this attempt, kept separate from the evidence of
# how it produced it. Copied, not moved: the workspace keeps its own copies.
for p in docs outputs firmware board.kicad_sch board.kicad_pcb schematic.intent.json; do
  [ -e "$p" ] && cp -r "$p" "$RUN/outputs/" 2>/dev/null
done

# ---------------------------------------------------------------- metadata
COPPERHEAD_RUN_META="$RUN/metadata.json" \
CH_BIN="$CH_BIN" CH_VERSION="$CH_VERSION" CH_HEAD="$CH_HEAD" CH_DIRTY="$CH_DIRTY" CH_BRANCH="$CH_BRANCH" \
WS_HEAD_BEFORE="$WS_HEAD_BEFORE" NODE_V="$NODE_V" KICAD_V="$KICAD_V" \
DISK_BEFORE="$DISK_BEFORE" TMP_BEFORE="$TMP_BEFORE" \
STARTED="$STARTED" ENDED="$ENDED" ELAPSED="$ELAPSED" EXIT="$EXIT" \
ATTEMPT="$N" VARIABLE="$VARIABLE" RUNDIR="$RUN" LOGFILE="$LOG" SESSION="$SESSION" \
 BRIEF="$BRIEF" WORKSPACE_PATH="$WORKSPACE" \
  node "$HARNESS/bin/lib/collect-metadata.mjs"

# Session index, rewritten each attempt so it never drifts from what is on disk.
SESSION="$SESSION" BRIEF="$BRIEF" BRIEF_SHA="$BRIEF_SHA" WORKSPACE="$WORKSPACE" \
  node "$HARNESS/bin/lib/update-session.mjs"

echo
echo "session $(basename "$SESSION") · attempt $N -> $RUN"
echo "  metadata: $RUN/metadata.json"
echo "  session:  $SESSION/session.json"
echo "  log:      $LOG"
node -e '
const m = require(process.env.M);
console.log(`  outcome:  ${m.outcome} (exit ${m.exit_code})`);
console.log(`  stages:   ${m.stages.completed}/${m.stages.total} — stopped in ${m.stages.stopped_in ?? "n/a"}`);
console.log(`  cost:     ${m.cost.turns} turns · ${m.cost.output_tokens_h} out · ${m.cost.wall} · cache ${m.cost.cache_hit_pct}%`);
' 2>/dev/null M="$RUN/metadata.json" || true

exit "$EXIT"
