# Copperhead create pipeline runbook

The short version. The full, falsifiable procedure is in
[E2E-AGENT-GUIDE.md](E2E-AGENT-GUIDE.md); this file is the orientation you read first.
Machine prerequisites are in [SETUP.md](SETUP.md).

## Goal

Drive `copperhead create` to a clean, complete end-to-end run: all 8 stages in order, exit
0, every stage committed, artifacts preserved.

## Layout

Three sibling directories. The split is deliberate and load-bearing:

| Path | Holds |
| --- | --- |
| `copperhead-test-harness/` | this runbook, the guide, `bin/`, `briefs/`, `run-logs/` — **invisible to the design agent** |
| `<workspace>/` | the design workspace: `brief.md`, `docs/`, the KiCad project |
| `copperhead/` | the CLI source under test |

Harness material stays out of the workspace because the design agent reads the workspace.
When the guides lived inside it, the stage-4 agent read them on turn 1 and applied the
harness rule "never hand-satisfy a gate" to its own `docs/BOM.md` — refusing to fix the doc,
then apologising for having touched it. When run evidence lived inside it, a stage attempt
died because `search` pulled ~600 K tokens of transcript into the prompt (I5).

`bin/new-workspace.sh` creates workspaces as siblings of the harness for exactly this
reason. Never create one inside the harness checkout.

## Running an attempt

```bash
bin/doctor.sh                                    # once per machine, and after any rebuild
bin/new-workspace.sh sensor-node                 # ../sensor-node, from briefs/sensor-node.md
bin/run-attempt.sh -w ../sensor-node -m claude-code:opus "baseline"
```

From inside a workspace the flags collapse — the script picks up `$PWD` when it holds the
brief:

```bash
cd ../sensor-node
../copperhead-test-harness/bin/run-attempt.sh "the one variable changed vs the last attempt"
```

The script handles preconditions, capture, evidence and metadata. It refuses to start if
`copperhead` does not both resolve and run.

Runs take hours. Launch in the background and let it finish — killing an attempt midway
skips the evidence copy, which is the only thing that makes a failure diagnosable.

### From any other folder

The harness is not tied to any one workspace. It locates itself, writes only absolute
paths, and takes the workspace as an argument — so it drives any brief from anywhere:

```bash
# a workspace that is not a sibling
run-attempt.sh -w ~/work/lamp-board -b brief.md "baseline"

# a copperhead checkout somewhere else
run-attempt.sh -w ~/work/lamp-board -s ~/src/copperhead "testing the PR build"

# keep a campaign's history outside the harness clone entirely
run-attempt.sh -w ~/work/lamp-board -o ~/campaigns/lamp "baseline"
```

| Flag | Default |
| --- | --- |
| `-w, --workspace DIR` | `$PWD` if it holds the brief, else `<harness>/../test` |
| `-b, --brief FILE` | `brief.md`, relative to the workspace |
| `-s, --src DIR` | `<harness>/../copperhead` |
| `-m, --model MODEL` | `claude-code` |
| `-o, --run-logs DIR` | `<harness>/run-logs` |
| `-h, --help` | usage |

`COPPERHEAD_WORKSPACE`, `COPPERHEAD_BRIEF`, `COPPERHEAD_SRC`, `COPPERHEAD_MODEL` and
`COPPERHEAD_RUNLOGS` do the same thing for callers that would rather not pass flags; a flag
beats the variable. Put `bin/` on `PATH` if you use this often.

Every workspace and brief gets its own session, so several boards can be driven from one
harness without their histories mixing — and `run-logs/` stays the single place to compare
them.

Attempts are grouped by **session** — one per brief. Every rerun against the same workspace
and the same brief lands in the same session directory, named for when that campaign
started, so one brief's whole history reads in one place:

```text
run-logs/<session>/          e.g. 2026-07-31T23-32-26
  session.json               brief identity + every attempt's outcome and variable
  attempt-01/ attempt-02/ …  create.log · metadata.json · REPORT.md · evidence/ · outputs/
```

The session is keyed on the brief's content hash, so editing the brief starts a new
session rather than folding into the previous campaign.

Resume is automatic — stages whose completion contract already holds are skipped and
committed. There is no resume flag; the same command continues from where it stopped.

**Never rebuild or branch-switch the copperhead checkout while a run is live.** The CLI
imports lazily, so a rebuild loads the new `dist/` into the already-running process and
silently contaminates the experiment.

## After an attempt

1. Read `run-logs/<session>/attempt-NN/metadata.json` — `outcome` and `definition_of_done`
   first. `session.json` shows the arc across attempts, including how far this brief has
   ever got (`best_stages_completed`).
2. Write `run-logs/<session>/attempt-NN/REPORT.md` using the guide's §6 template. Do not
   restate metadata fields; the report is for judgement, not numbers.
3. Diagnose to a named mechanism. "It timed out" is a symptom.
4. Record it: a defect goes in `run-logs/ISSUES-FOUND.md` with a status flag, an
   improvement in `run-logs/RECOMMENDATIONS.md`. Start them from
   [`templates/`](../templates/) on a new campaign. Update flags in place; never duplicate
   an entry.
5. Apply the smallest fix, preferring the copperhead repo over the workspace. Add a
   regression test. Rebuild, relink, re-verify that `copperhead --version` runs.
6. Rerun, changing exactly one variable.

Write the report after **every** attempt, including ones you killed or that died on the
environment. An attempt with no report is an attempt whose evidence nobody will read again.

## Success criteria

All five, or it is a failed attempt:

1. exit code 0
2. all 8 stages complete
3. `all checks green` (not `with check failures`)
4. every stage committed, working tree clean of pipeline artifacts
5. `REPORT.md`, `report.json` and per-stage `transcript.jsonl` preserved

`metadata.json` evaluates all five under `definition_of_done`. Read that rather than
eyeballing the log.

## What does not count

- Hand-editing `docs/`, or dropping files into `outputs/`/`firmware/`, so a gate passes. The
  gates are proxies for agent work; satisfying the proxy by hand invalidates the test.
- Deleting artifacts to force a re-run without recording what and why.
- A stage reporting "already complete" on a fresh workspace.
- The agent reporting success where the exit code was non-zero. **Agent self-reports are not
  status** — one narrated "Clean sheet: no legibility findings, score 91" directly below
  tool output reading `cap: 40 — 3 error-severity findings`, and another recorded probes it
  never made as a verified constraint, which the recovery supervisor then consumed to abort
  a healthy run. Read `metadata.json` and the transcript, never the narration.

## Stop conditions

Stop and report a blocker rather than looping:

- the same mechanism recurs 3 times with no fix that advances the pipeline
- a fix would require hand-editing workspace artifacts to satisfy a gate
- the failure is external: provider outage, missing `kicad-cli`, unfreeable disk
- two consecutive attempts reach a strictly earlier stage than their predecessor
