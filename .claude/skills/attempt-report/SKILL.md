---
name: attempt-report
description: Write the REPORT.md for a finished copperhead create attempt and update the ISSUES-FOUND / RECOMMENDATIONS registers. Use after an attempt completes, is killed, or dies on the environment — e.g. /attempt-report, or "write up attempt 4".
allowed-tools: Bash(git:*), Bash(jq:*), Bash(node:*), Bash(ls:*), Read, Grep, Glob, Edit, Write
compatibility: Reads a completed run-logs/<session>/attempt-NN/ directory produced by bin/run-attempt.sh.
metadata:
  author: copperhead-test-harness
  version: "1.0"
---

Write `run-logs/<session>/attempt-NN/REPORT.md` for the attempt, then update the registers.
Do this after **every** attempt — pass, fail, killed, or died on the environment. An attempt
with no report is an attempt whose evidence nobody will read again.

## Ground every claim in the evidence

Read, in this order: `metadata.json` (`outcome`, `definition_of_done` first), then
`evidence/*/transcript.jsonl`, then `create.log`. Do **not** take the agent's narration as
status — it has claimed clean results directly below tool output contradicting them, and has
recorded probes it never made as verified constraints.

```bash
jq '.outcome, .definition_of_done, .stages, .reliability' <run>/metadata.json
jq -r '.type' <run>/evidence/*/transcript.jsonl | sort | uniq -c | sort -rn
jq -r 'select(.type|test("fail|refused|timeout|limit|restore")) | "\(.ts) \(.type) \(.data|tostring[0:300])"' \
   <run>/evidence/*/transcript.jsonl
```

Anything the report asserts must be checkable from `evidence/` without re-running.

## The report

Do **not** restate what `metadata.json` already holds — exit code, stage counts, turns,
tokens, cache, timeouts, commits, disk. Those are captured automatically and a hand-copied
number is one more thing that can be wrong. The report carries the judgement the metadata
cannot make.

```markdown
# Attempt NN — <PASS | FAIL>

Metadata: ./metadata.json   Log: ./create.log   Evidence: ./evidence/

## What happened
<Three or four sentences. Which stage, which of its attempts, and what stopped it.>

## Failure mechanism
<One named mechanism, not a symptom. "It timed out" is a symptom; "the cumulative
watchdog budget of 3 fired on three independently slow capture turns" is a mechanism.>

## Evidence
<Log line refs, transcript event types, file:line in copperhead.>

## Root cause
<The defect, or environment / budget / provider. If the diagnosis is a guess, say so.>

## New or recurrence
<NEW → add to ISSUES-FOUND.md with a status flag | recurrence of I<n> → update that entry>

## Action taken
<The smallest fix, file:line and commit. Or "none — investigation only".>

## Validated
<Which run confirmed it, or "not yet — no run has passed this point since the fix".
A unit test is not validation.>

## Next attempt
<The single variable to change.>
```

The report must answer, somewhere: which stage, which of its three attempts, which turn;
the mechanism class (timeout / contract-unmet / tool defect / rollback / resource exhaustion
/ provider / budget / context overflow); whether work was lost or left uncommitted
(`evidence/git-stash.txt`, `evidence/git-status.txt`); new or a recurrence, with the issue
ID; and the smallest change that would have prevented it.

## Then update the registers

A defect goes in `run-logs/ISSUES-FOUND.md`, an improvement that is not a defect in
`run-logs/RECOMMENDATIONS.md`. If they do not exist yet, start them from `templates/`.

- **Update the flag in place.** Never open a second entry for the same defect. Never delete
  one that turned out to be wrong — mark it `INVALID` and say what was actually true.
- **Edit the summary table and the detail in the same change**, or the register lies at a
  glance, which is how most people read it.
- **`FIXED` ≠ `VALIDATED`.** A landed fix with a passing unit test earns `FIXED`. Only a run
  that gets past the blockage earns `VALIDATED`, and it must cite that run. A register full
  of `FIXED` with no `VALIDATED` is an honest statement that nothing is proven end to end.
- **`BY-CONTRACT` needs a location.** "Enforced in the stage-3 prompt" is a status;
  "handled elsewhere" is not.

Document only new findings grounded in observed evidence. No speculation.
