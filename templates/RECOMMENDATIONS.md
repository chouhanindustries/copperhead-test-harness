# Recommendations — `copperhead create` end-to-end

<!--
Copy this to run-logs/RECOMMENDATIONS.md when you start a campaign.
-->

Improvements that are not defects. A defect goes in [ISSUES-FOUND.md](ISSUES-FOUND.md); this
file is for things that work as designed and could work better.

Each entry carries a **Priority** and a **Status**, updated in place.

**Priority** — `P0` blocks or corrupts a run · `P1` large cost or latency win · `P2`
robustness or ergonomics · `P3` polish.

**Status** — `OPEN` (no work landed) · `DONE` (landed; cite the commit) · `PARTIAL` (some of
it landed; say what remains) · `DECLINED` (deliberately not doing it; say why) ·
`SUPERSEDED` (another change made it moot; say which).

## Register

| ID | Priority | Status | Summary | From | Landed as |
| --- | --- | --- | --- | --- | --- |
| [R1](#r1--short-title) | P1 | `OPEN` | One line, readable at a glance | [attempt-01](<session>/attempt-01/) | — |

---

## R1 — short title

**Priority** P1 · **Status** `OPEN` · **From** [`<session>/attempt-01/`](<session>/attempt-01/)

### What it costs today

<The observed cost — tokens, wall time, a class of failure it invites. Grounded in a run,
not in principle.>

### What to do instead

<The change, concretely enough that someone else could implement it. `file:line` where you
know it.>

### Why this is not a defect

<It works as designed. Say what the design is, so the entry does not drift into
ISSUES-FOUND.md later.>
