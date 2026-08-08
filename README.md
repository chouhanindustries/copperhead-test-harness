# copperhead-test-harness

A test harness for driving [`copperhead create`](https://github.com/chouhanindustries/copperhead)
— the eight-stage AI KiCad schematic pipeline — to a clean end-to-end run, and for capturing
enough evidence when it fails that someone else can diagnose it without re-running.

Runs take hours and cost real tokens. The harness exists so that no attempt is wasted: it
verifies preconditions before launching, captures the real exit code, copies the evidence
before anything can overwrite it, and writes a machine-readable record of what ran against
what.

## Quickstart

```bash
git clone <this repo> && cd copperhead-test-harness

bin/doctor.sh                             # preflight — fails loudly on a bad environment
bin/new-workspace.sh sensor-node          # ../sensor-node, from briefs/sensor-node.md
bin/run-attempt.sh -w ../sensor-node -m claude-code:opus "baseline"
```

Everything the attempt produced lands in `run-logs/<session>/attempt-01/`. Read
`metadata.json` — `outcome` and `definition_of_done` — not the log, and not the agent's
narration.

Full prerequisites: [docs/SETUP.md](docs/SETUP.md).

## What's here

```text
bin/
  doctor.sh              preflight: CLI, toolchain, symbol libraries, disk, RAM, workspace
  new-workspace.sh       create a design workspace from a brief, as a sibling of the harness
  run-attempt.sh         one attempt, fully captured
  lib/                   metadata collectors, called by run-attempt.sh
docs/
  RUNBOOK.md             orientation: layout, the loop, success criteria, stop conditions
  E2E-AGENT-GUIDE.md     the falsifiable procedure — stage contracts, triage, report template
  SETUP.md               machine prerequisites
briefs/                  design briefs to drive the pipeline with
templates/               ledger skeletons for ISSUES-FOUND.md and RECOMMENDATIONS.md
.claude/skills/          run-attempt and attempt-report, for driving this under Claude Code
run-logs/                where attempts land — not tracked
```

## How it is meant to be used

Three sibling directories, and the split matters:

```text
<parent>/
  copperhead/                 the CLI source under test
  copperhead-test-harness/    this repo — invisible to the design agent
  sensor-node/                a design workspace: brief.md, docs/, the KiCad project
```

Harness material stays out of the design workspace because the design agent reads the
workspace. When the guides lived inside it, the stage-4 agent read them on turn 1 and
applied a harness rule to its own BOM. When run evidence lived inside it, a stage died
pulling ~600 K tokens of transcript into the prompt.

The loop is: run one attempt, read `metadata.json`, diagnose to a **named mechanism**, apply
the smallest fix, write the report, change exactly one variable, rerun. Resume is automatic
— stages whose completion contract already holds are skipped.

Read [docs/RUNBOOK.md](docs/RUNBOOK.md) before the first attempt, and
[docs/E2E-AGENT-GUIDE.md](docs/E2E-AGENT-GUIDE.md) before diagnosing one.

## What this repo does not carry

`run-logs/` is untracked. Attempt transcripts and evidence are large, per-machine, and merge
hostile, and the `I<n>`/`R<n>` registers do not reconcile across contributors — so each
checkout keeps its own campaign history. Start the registers from `templates/` and file real
defects upstream against copperhead, where they are shared.

## Ground rules

These are not style preferences; each one is a way an attempt has been lost.

- **One variable per attempt.** An attempt that changes two things cannot attribute its
  outcome to either.
- **Never hand-satisfy a completion gate.** The gates are proxies for agent work. Editing
  `docs/` or dropping files into `outputs/` to make a stage pass invalidates the test.
- **Agent self-reports are not status.** Read `metadata.json` and the transcript. A report
  has claimed a clean sheet directly below tool output showing error-severity findings.
- **Never rebuild or switch branches while a run is live.** Lazy imports load the new
  `dist/` into the running process and contaminate the experiment.
- **`FIXED` is not `VALIDATED`.** Only a run that gets past the blockage validates a fix,
  and it must cite that run.
- **Write the report even when the attempt died.** Especially then.
