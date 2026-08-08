# Issues found — `copperhead create` end-to-end

<!--
Copy this to run-logs/ISSUES-FOUND.md when you start a campaign, then fill in the
header below. One register per harness checkout, not per session — the point is
that a defect seen driving one brief is findable when it recurs on another.
-->

Workspaces: `<name>/`, brief = `<what it asks for>` (I1–…).
CLI under test: `copperhead <version>` on `<branch>` @ `<sha>`.

Every issue carries a **Status** flag. Update the flag in place when it changes — never add
a second entry for the same defect, and never delete one that turned out to be invalid (say
so instead; a wrong diagnosis is worth keeping).

**Severity** — `BLOCKER` stalls the pipeline · `DEFECT` wrong or corrupt output that still
completes · `INEFFICIENCY` wasted time or tokens · `NOTE` observation, no action expected.

**Status** — one of:

| Flag | Meaning |
| --- | --- |
| `OPEN` | reproduced, no fix landed |
| `FIXED` | fix landed; cite the commit. Says nothing about whether a run has confirmed it |
| `VALIDATED` | `FIXED`, **and** a later run got past it. Cite the run |
| `BY-CONTRACT` | not fixed in code by choice — the rule is enforced elsewhere (a prompt, a doc contract). Say where |
| `WONTFIX` | real, deliberately not fixed. Say why |
| `INVALID` | the diagnosis was wrong. Keep the entry, say what was actually true |

A fix is not `VALIDATED` by its unit test. The test proves the code does what it says; only
a run proves it removed the blockage.

## Register

| ID | Severity | Status | Summary | Found in | Fix |
| --- | --- | --- | --- | --- | --- |
| [I1](#i1-short-kebab-case-title) | BLOCKER | `OPEN` | One line, readable at a glance | [attempt-01](<session>/attempt-01/) | — |

The summary table is part of the entry: change a detail below and change its row here in the
same edit, or the register lies at a glance — which is how most people read it.

---

## I1 — short kebab-case title

**Severity** BLOCKER · **Status** `OPEN` · **Found in** [`<session>/attempt-01/`](<session>/attempt-01/)

### What happens

<The observable behaviour. Quote the log line or transcript event, not a paraphrase.>

### Mechanism

<Why it happens, named. "It timed out" is a symptom; "the cumulative watchdog budget of 3
fired on three independently slow capture turns" is a mechanism. Cite `file:line` in
copperhead where you can.>

### Evidence

<Log refs, transcript event types, file:line. Anything asserted here must be checkable from
the attempt's `evidence/` without re-running.>

### Fix

<`file:line` and commit, or "none". If `FIXED`, say which run must pass to make it
`VALIDATED` — and say plainly when a later run did not.>
