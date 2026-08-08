---
name: run-attempt
description: Launch one copperhead create attempt under the harness and report its outcome. Use when the user asks to run an attempt, drive a brief, rerun after a fix, or start a campaign — e.g. /run-attempt sensor-node, or "run it again with the symbol fix".
allowed-tools: AskUserQuestion, Bash(git:*), Bash(node:*), Bash(npm:*), Bash(jq:*), Bash(bin/*), Bash(df:*), Bash(free:*), Bash(ls:*), Read, Grep, Glob
compatibility: Requires a built copperhead on PATH, kicad-cli, and the full KiCad symbol library set. Run bin/doctor.sh first.
metadata:
  author: copperhead-test-harness
  version: "1.0"
---

Launch exactly one `copperhead create` attempt through `bin/run-attempt.sh` and report what
it did. The full procedure is [`docs/E2E-AGENT-GUIDE.md`](../../../docs/E2E-AGENT-GUIDE.md);
the short form is [`docs/RUNBOOK.md`](../../../docs/RUNBOOK.md).

## Before launching

1. **Run `bin/doctor.sh -w <workspace>`.** Do not launch with a FAIL line outstanding. A
   stale `dist/` means the run tests code nobody is reading; a reduced symbol library set
   produces a failure that reads as a model defect and is not one.
2. **Establish the one variable.** Every attempt changes exactly one thing versus the
   previous: one copperhead fix, one config value, one environment condition. If the user
   has not said what changed, ask — an attempt that changes two things cannot attribute its
   outcome to either. For the first attempt in a session the variable is `baseline`.
3. **Check nothing is already running.** Two attempts against one workspace corrupt each
   other's git snapshots. `pgrep -af copperhead`.
4. **Confirm the model.** Default to `-m claude-code:opus` unless the user says otherwise;
   record any deviation as the variable.

## Launching

```bash
bin/run-attempt.sh -w <workspace> -m claude-code:opus "<the one variable changed>"
```

Run it **in the background** — attempts take hours. Do not poll it in a tight loop, and do
not kill it: an interrupted attempt skips the evidence copy, which is what makes a failure
diagnosable afterwards.

While it runs, do not rebuild, `npm link`, or switch branches in the copperhead checkout.
The CLI imports lazily, so a rebuild loads new code into the running process and silently
contaminates the experiment.

## When it finishes

Read `metadata.json`, never the agent's narration. Self-reports in this pipeline have
claimed clean sheets directly below tool output showing error-severity findings, and have
recorded probes that were never made as verified constraints.

```bash
jq '.outcome, .definition_of_done, .stages, .reliability' <run>/metadata.json
jq '.best_stages_completed, (.history[] | {attempt, outcome, variable_changed, stages_completed})' <session>/session.json
```

`outcome` is `PASS` only on exit 0 **and** `all checks green`. Eight stages with check
failures reports `COMPLETE_WITH_CHECK_FAILURES`, which is not a pass.

Then diagnose to a named mechanism from the evidence, using the guide's §5.2 transcript
greps and §5.3 triage table:

```bash
jq -r '.type' <run>/evidence/*/transcript.jsonl | sort | uniq -c | sort -rn
jq -r 'select(.type|test("fail|refused|timeout|limit|restore")) | "\(.ts) \(.type) \(.data|tostring[0:300])"' \
   <run>/evidence/*/transcript.jsonl
```

## Report

Hand off to the `attempt-report` skill — every attempt gets a `REPORT.md`, including one
that was killed or died on the environment.

## Stop rather than loop

Report a blocker instead of launching another attempt when: the same mechanism recurs three
times with no fix that advances the pipeline; a fix would require hand-editing workspace
artifacts to satisfy a gate; the failure is external (provider outage, missing `kicad-cli`,
unfreeable disk); or two consecutive attempts reach a strictly earlier stage than their
predecessor.

Never satisfy a completion gate by hand to make a run go green. The gates are proxies for
agent work; satisfying the proxy invalidates the test.
