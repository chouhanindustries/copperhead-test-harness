# Setup

What a machine needs before it can drive an attempt. `bin/doctor.sh` checks every item on
this page; run it rather than trusting this list.

## Layout

The harness expects to sit beside the copperhead checkout, and creates design workspaces as
its siblings:

```text
<parent>/
  copperhead/                 the CLI source under test
  copperhead-test-harness/    this repo
  sensor-node/                a design workspace, created by bin/new-workspace.sh
```

Nothing enforces this — `--src` and `--workspace` point anywhere — but the defaults assume
it, and the separation between harness and workspace is load-bearing (see
[RUNBOOK.md](RUNBOOK.md#layout)).

## Prerequisites

| Requirement | Why | Check |
| --- | --- | --- |
| Node ≥ 20 | runs the CLI and the harness's metadata collectors | `node -v` |
| `copperhead` on `PATH`, resolving to a dev build | the thing under test | `readlink -f "$(which copperhead)"` → `.../copperhead/dist/cli.js` |
| KiCad ≥ 8 with `kicad-cli` | stages 4–6 run ERC, DRC and Gerber export | `kicad-cli --version` |
| The **full** KiCad symbol library set (~222 `.kicad_sym`) | stage 3 picks parts by `lib_id` and stage 4 must resolve them | `ls /usr/share/kicad/symbols/*.kicad_sym \| wc -l` |
| ≥ 2 GiB free disk (5 GiB for a campaign) | `create` refuses below 2 GiB; stages 4–6 render SVGs per attempt | `df -h .` |
| ≥ 2 GiB free RAM | agent spawns fail under memory pressure | `free -h` |
| Anthropic credentials for the model you pass to `--model` | the pipeline is agent-driven | — |

### Two that bite

**A reduced symbol library set looks like a model failure.** If KiCad was installed without
its libraries, stage 3 commits `lib_id`s that stage 4 cannot resolve, and the transcript
reads as the agent hallucinating parts. It is an environment problem. `doctor.sh` warns
below 200 libraries.

**`readlink` alone does not prove the CLI works.** A `dist/cli.js` that lost its executable
bit still satisfies the symlink while `which copperhead` returns nothing. Check
`copperhead --version` too — `run-attempt.sh` refuses to start if either fails.

## Building the CLI under test

```bash
cd ../copperhead
npm install
npm run build && npm link
copperhead --version          # verify it runs, not just that the symlink resolves
```

Repeat the build **and** the verify after every source change. `doctor.sh` fails when
`dist/` is older than `src/`.

## First run

```bash
bin/doctor.sh
bin/new-workspace.sh sensor-node          # ../sensor-node, from briefs/sensor-node.md
bin/run-attempt.sh -w ../sensor-node -m claude-code:opus "baseline"
```

Runs take hours. Launch in the background; killing an attempt midway skips the evidence
copy, and the evidence is the only thing that makes a failure diagnosable afterwards.

## Choosing a model

Pass it with `-m`. As of the last campaign, `claude-code:opus` is the working default:
another model in the same family began deterministically safeguard-flagging the stage-4
prompt, which reads as a pipeline failure and is not one. If a stage refuses on prompt
content rather than on its work, try a different model before diagnosing copperhead.

## Ledgers

The two registers live in `run-logs/` and are not tracked here — a campaign's findings are
yours, and `I<n>`/`R<n>` numbering does not merge across contributors. Start them from
[`../templates/`](../templates/):

```bash
cp templates/ISSUES-FOUND.md templates/RECOMMENDATIONS.md run-logs/
```

If several people are driving the same copperhead, agree on non-overlapping number ranges
up front, or keep one register per contributor and reconcile in the upstream issue tracker.
