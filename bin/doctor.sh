#!/usr/bin/env bash
#
# Preflight for a `copperhead create` attempt.
#
# Every check here corresponds to a way a run has actually been lost. Run it
# before the first attempt on a new machine, and again after any rebuild —
# a multi-hour run that dies on a missing symbol library is the expensive way
# to learn the library set is incomplete.
#
# Usage:
#   doctor.sh [-s <copperhead src>] [-w <workspace>]
#
#   -s, --src DIR         copperhead source under test   (default: <harness>/../copperhead)
#   -w, --workspace DIR   also check this design workspace   (default: none)
#
# Exit 0 if every hard check passes. Exit 1 if any does. Warnings do not fail.
#
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${COPPERHEAD_SRC:-}"
WORKSPACE="${COPPERHEAD_WORKSPACE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--src)       SRC="$2";       shift 2 ;;
    -w|--workspace) WORKSPACE="$2"; shift 2 ;;
    -h|--help)      sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *)              echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
SRC="${SRC:-$HARNESS/../copperhead}"

FAILED=0
pass() { printf '  \033[32mok\033[0m    %s\n' "$1"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILED=1; }

echo "copperhead harness preflight"
echo

# ------------------------------------------------------------------ the CLI
# `readlink` alone is not enough: a dist/cli.js that lost its executable bit
# still satisfies the symlink while `which copperhead` returns nothing (I6).
echo "CLI"
CH_BIN="$(readlink -f "$(command -v copperhead)" 2>/dev/null || true)"
CH_VERSION="$(copperhead --version 2>/dev/null || true)"
if [ -z "$CH_BIN" ]; then
  fail "copperhead does not resolve — run 'npm run build && npm link' in $SRC"
elif [ -z "$CH_VERSION" ]; then
  fail "copperhead resolves to $CH_BIN but does not run (lost its executable bit?)"
else
  pass "copperhead $CH_VERSION -> $CH_BIN"
  case "$CH_BIN" in
    */dist/cli.js) ;;
    *) warn "not a dist/ build — this may be a published install, not the source under test" ;;
  esac
fi

if [ -d "$SRC/.git" ]; then
  CH_BRANCH="$(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  CH_HEAD="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null)"
  CH_DIRTY="$(git -C "$SRC" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  pass "source $CH_BRANCH @ $CH_HEAD"
  [ "$CH_DIRTY" != 0 ] && warn "$CH_DIRTY uncommitted files in $SRC — the attempt is not reproducible from that sha"
  # A dist/ older than src/ means the running CLI is not the code you are reading.
  if [ -d "$SRC/dist" ] && [ -n "$(find "$SRC/src" -newer "$SRC/dist" -name '*.ts' -print -quit 2>/dev/null)" ]; then
    fail "dist/ is older than src/ — rebuild before running ('npm run build && npm link')"
  fi
else
  warn "no git checkout at $SRC — pass --src, or the attempt cannot record what it ran against"
fi
echo

# ------------------------------------------------------------------ toolchain
echo "Toolchain"
if command -v node >/dev/null; then pass "node $(node -v)"; else fail "node not found"; fi
if command -v kicad-cli >/dev/null; then
  pass "kicad-cli $(kicad-cli --version 2>&1 | head -1)"
else
  fail "kicad-cli not found — stages 4, 5 and 6 (ERC, DRC, export) cannot run"
fi

# Symbol libraries. Stage 3 picks parts by lib_id and stage 4 must resolve them;
# a reduced library set makes real parts unfindable and looks like a model
# failure rather than an environment one (I19, I20).
SYMDIR=""
for d in "${KICAD9_SYMBOL_DIR:-}" "${KICAD8_SYMBOL_DIR:-}" "${KICAD_SYMBOL_DIR:-}" \
         /usr/share/kicad/symbols /usr/local/share/kicad/symbols \
         /Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols; do
  [ -n "$d" ] && [ -d "$d" ] && { SYMDIR="$d"; break; }
done
if [ -z "$SYMDIR" ]; then
  fail "no KiCad symbol library directory found — set KICAD9_SYMBOL_DIR"
else
  NLIB="$(find "$SYMDIR" -maxdepth 1 -name '*.kicad_sym' | wc -l | tr -d ' ')"
  if [ "$NLIB" -lt 200 ]; then
    warn "$NLIB symbol libraries in $SYMDIR — the stock set is ~222; parts will be unresolvable"
  else
    pass "$NLIB symbol libraries in $SYMDIR"
  fi
fi
echo

# ------------------------------------------------------------------ resources
echo "Resources"
# create's preflight refuses below 2 GiB, and stages 4-6 render SVGs per attempt.
FREE_MB="$(df -Pm . | tail -1 | awk '{print $4}')"
if [ "$FREE_MB" -lt 2048 ]; then
  fail "${FREE_MB} MB free — create's preflight refuses below 2048 MB"
elif [ "$FREE_MB" -lt 5120 ]; then
  warn "${FREE_MB} MB free — a multi-attempt campaign will exhaust this"
else
  pass "${FREE_MB} MB free"
fi

# A failed agent spawn under memory pressure surfaces as the misleading SDK
# error "native binary failed to launch (libc mismatch)". It is not a libc bug.
if command -v free >/dev/null; then
  AVAIL_MB="$(free -m | awk '/^Mem:/ {print $7}')"
  if [ "${AVAIL_MB:-0}" -lt 2048 ]; then
    warn "${AVAIL_MB} MB RAM available — agent spawns fail under pressure and report a bogus libc mismatch"
  else
    pass "${AVAIL_MB} MB RAM available"
  fi
fi

# I9: temp directories are not swept below a 2h age gate; they accumulate.
NTMP="$(ls -d /tmp/copperhead-* 2>/dev/null | wc -l | tr -d ' ')"
if [ "$NTMP" -gt 20 ]; then
  warn "$NTMP /tmp/copperhead-* directories left over (I9) — clear them before a long campaign"
else
  pass "$NTMP /tmp/copperhead-* directories"
fi
echo

# ------------------------------------------------------------------ workspace
if [ -n "$WORKSPACE" ]; then
  echo "Workspace $WORKSPACE"
  if [ ! -d "$WORKSPACE" ]; then
    fail "does not exist — create one with bin/new-workspace.sh"
  elif ! git -C "$WORKSPACE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail "not a git repo — create refuses to run outside one"
  elif ! git -C "$WORKSPACE" log --oneline -1 >/dev/null 2>&1; then
    fail "no commits — create refuses; commit the brief as a baseline"
  else
    pass "git repo @ $(git -C "$WORKSPACE" rev-parse --short HEAD)"
    [ -f "$WORKSPACE/brief.md" ] && pass "brief.md present" || warn "no brief.md — pass --brief explicitly"
    # Rollback is `git reset --hard` + `git clean -fd`: untracked work is destroyed
    # by the first stage failure.
    NUNTRACKED="$(git -C "$WORKSPACE" ls-files --others --exclude-standard | wc -l | tr -d ' ')"
    [ "$NUNTRACKED" -gt 0 ] && warn "$NUNTRACKED untracked files — a rollback's 'git clean -fd' will destroy them"
  fi
  echo
fi

if [ "$FAILED" = 0 ]; then echo "ready."; else echo "not ready — fix the FAIL lines above."; fi
exit "$FAILED"
