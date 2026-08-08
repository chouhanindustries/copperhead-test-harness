#!/usr/bin/env bash
#
# Create a design workspace from a brief.
#
# A workspace is a git repo holding one brief and nothing else; everything after
# that — docs/, the KiCad project, outputs/, firmware/ — is what the pipeline
# produces. `create` refuses to run outside a git repo with at least one commit,
# and its rollback is `git reset --hard` + `git clean -fd`, so the baseline
# commit is what a failed stage rolls back to.
#
# Workspaces are gathered under <harness>/workspaces/, which is not tracked.
# What matters is that no harness material lands INSIDE a workspace: when the
# guides lived in one, the stage-4 agent read them on turn 1 and applied a
# harness rule to its own BOM, and when run evidence lived there a stage died
# pulling ~600 K tokens of transcript into the prompt (I5). Keeping every
# workspace one level down, beside the others, holds that line and keeps the
# harness root readable.
#
# Usage:
#   new-workspace.sh <brief> [name]
#
#   <brief>   a file, or the stem of one in briefs/ (e.g. `sensor-node`)
#   [name]    workspace directory name   (default: the brief's stem)
#
#   -d, --dir DIR   where to create it   (default: <harness>/workspaces)
#
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$HARNESS/workspaces"
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--dir)  PARENT="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*)        echo "unknown option: $1" >&2; exit 2 ;;
    *)         ARGS+=("$1"); shift ;;
  esac
done
[ "${#ARGS[@]}" -ge 1 ] || { echo "usage: new-workspace.sh <brief> [name]" >&2; exit 2; }

# Resolve the brief: a path if it exists, otherwise a stem in briefs/.
BRIEF="${ARGS[0]}"
if [ ! -f "$BRIEF" ]; then
  if [ -f "$HARNESS/briefs/$BRIEF.md" ]; then
    BRIEF="$HARNESS/briefs/$BRIEF.md"
  elif [ -f "$HARNESS/briefs/$BRIEF" ]; then
    BRIEF="$HARNESS/briefs/$BRIEF"
  else
    echo "no brief at $BRIEF, and none in $HARNESS/briefs/" >&2
    echo "available:" >&2
    for b in "$HARNESS"/briefs/*.md; do [ -f "$b" ] && echo "  $(basename "${b%.md}")" >&2; done
    exit 2
  fi
fi
BRIEF="$(cd "$(dirname "$BRIEF")" && pwd)/$(basename "$BRIEF")"

NAME="${ARGS[1]:-$(basename "${BRIEF%.md}")}"
mkdir -p "$PARENT" || { echo "cannot create $PARENT" >&2; exit 2; }
PARENT="$(cd "$PARENT" && pwd)"
DEST="$PARENT/$NAME"
[ -e "$DEST" ] && { echo "$DEST already exists — pick another name, or drive the existing workspace" >&2; exit 2; }

mkdir -p "$DEST"
cp "$BRIEF" "$DEST/brief.md"

# KiCad keeps a git-backed .history/ inside the project. Left untracked it grows
# without bound and breaks the pipeline's `git add -A` commit step.
cat > "$DEST/.gitignore" <<'EOF'
.history/
EOF

git -C "$DEST" init -q
git -C "$DEST" add -A
git -C "$DEST" -c user.name="copperhead-harness" -c user.email="harness@localhost" \
  commit -q -m "workspace baseline: brief"

echo "workspace $DEST @ $(git -C "$DEST" rev-parse --short HEAD)"
echo
echo "  $HARNESS/bin/doctor.sh -w $DEST"
echo "  $HARNESS/bin/run-attempt.sh -w $DEST -m claude-code:opus \"baseline\""
