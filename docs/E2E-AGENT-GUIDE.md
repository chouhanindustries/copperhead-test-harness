# End-to-end run guide: `copperhead create` under an agent orchestrator

This guide defines how to drive the copperhead create pipeline to a clean, complete
end-to-end run while an agent orchestrates the loop: launch, observe, capture, diagnose,
patch, rebuild, rerun.

It is written to be **falsifiable**. Every success claim in this document maps to a
command whose output another engineer can reproduce. Where the guide says "verify", it
means run the command and paste the output into the attempt log — not assert it.

Companion runbook: [RUNBOOK.md](RUNBOOK.md). Known-issue register:
`../run-logs/ISSUES-FOUND.md`. Recommendations: `../run-logs/RECOMMENDATIONS.md`.

## Where things live

The layout, and why the split matters:

| Path | Holds | Note |
| --- | --- | --- |
| `copperhead-test-harness/` | this guide, `RUNBOOK.md`, `bin/`, `run-logs/` | **not visible to the design agent** |
| `copperhead-test-harness/workspaces/<name>/` | `brief.md`, `docs/`, the KiCad project | the design workspace `create` runs in; make one with `bin/new-workspace.sh` |
| `copperhead/` | the CLI source under test | `npm run build && npm link` |

Harness docs and run evidence sit **outside** the design workspace deliberately. When they
sat inside it, two things went wrong: the stage-4 agent read this guide on turn 1 and
applied its "never hand-satisfy a gate" rule to its own `docs/BOM.md` — refusing to fix the
doc, then apologising for having touched it — and a later attempt died on `Prompt is too
long · ~1003121 tokens` because `search` reached the preserved transcripts in `run-logs/`.
Neither was the agent's fault; both were the harness leaking into the design.

**Every shell block below runs from the design workspace** (`cd workspaces/<name>` from the
harness root), not from this directory: `brief.md` and `git -C .` are relative to it, and
the copperhead checkout is `../../../copperhead`. The exception is the attempt log, which is
written to the harness's `run-logs/` — outside the workspace repo, so a rollback's
`git clean -fd` cannot delete the evidence of the failure that caused it.

---

## 1. Definition of done

A run counts as complete when **all** of the following hold, each verified by the stated
command:

| # | Condition | Verification |
| --- | ----------- | -------------- |
| 1 | The CLI exited 0 | `echo "exit=$?"` captured in the attempt log immediately after the run |
| 2 | All 8 stages reached and passed their completion contract | `create pipeline complete` line in the log; 8 rows in the cost table |
| 3 | Final check gate green | `create pipeline complete; all checks green` (not `with check failures`) |
| 4 | Every stage committed | `git log --oneline` shows a commit per stage; `git status --porcelain` is clean of pipeline artifacts |
| 5 | Artifacts preserved | `.copperhead/runs/REPORT.md`, `report.json`, and per-stage `transcript.jsonl` all exist |

**Anything short of all five is a failed attempt**, including a run that completes 8
stages with `check failures`. Record it as such.

All five are evaluated automatically into `run-logs/<session>/attempt-NN/metadata.json`:

```bash
jq '.outcome, .definition_of_done' run-logs/<session>/attempt-NN/metadata.json
```

Read that rather than eyeballing the log. `outcome` is `PASS` only when the CLI exited 0
**and** the log carries `all checks green`; a run that finishes 8 stages with check failures
reports `COMPLETE_WITH_CHECK_FAILURES`, which is not a pass.

### 1.1 What does *not* count as success

These are the ways this pipeline has historically produced a false green. Treat each as a
failed attempt, not a pass:

- **Hand-satisfying a gate.** Editing `docs/SPEC.md`, `BOM.md`, `LAYOUT.md`, `DEVPLAN.md`,
  the schematic, or dropping files into `outputs/`/`firmware/` so that `isComplete()`
  returns true. The gates are proxies for agent work; satisfying the proxy by hand
  invalidates the test. If you must do it to unblock investigation, do it in a scratch
  copy and say so explicitly.
- **Deleting artifacts to force a re-run** without recording what was deleted and why.
- **A stage that "already complete (resuming past it)"** on the very first attempt in a
  fresh workspace — that means a scaffold or a stale artifact is satisfying the gate, not
  real work. Investigate before proceeding.
- **The agent reporting success** where the CLI exit code was non-zero. The exit code is
  authoritative.
- **A green run whose schematic never passed `verify_symbols`** (see I4: a placeholder
  symbol carries no pin types, so ERC type-checks nothing about that part).

---

## 2. The pipeline you are testing

Eight stages, in order, from `src/commands/create.ts` (`STAGES`). Each has a
machine-checkable completion contract — the pipeline will **not** advance on a
"successful" agent run that fails its contract.

| # | Stage | Primary artifact | Completion contract (`isComplete`) |
| --- | ------- | ------------------ | ------------------------------------ |
| 1 | `spec-seed` | `docs/SPEC.md` | A `Budgets` heading **plus** ≥1 non-comment, non-blank line beneath it |
| 2 | `architecture` | `docs/SUBSYSTEMS.md` | ≥1 `##`+ heading **plus** ≥1 real prose line (scaffold text and `- Ref: Value` bullets don't count) |
| 3 | `part-selection` | `docs/BOM.md` | ≥1 table row whose MPN column is not `UNVERIFIED*` |
| 4 | `schematic` | `*.kicad_sch` | Symbols present **and** drift-clean (`checkDrift`) **and** `run_erc` OK |
| 5 | `layout-draft` | `*.kicad_pcb`, `docs/LAYOUT.md` | Board contains `(footprint` **and** `LAYOUT.md` has a populated `## Draft quality` section |
| 6 | `outputs` | `outputs/` | ≥1 Gerber file (`.gbr`/`.gtl`/`.gbl`/…) |
| 7 | `firmware` | `firmware/` | ≥1 source file (`.c`/`.h`/`.cpp`/`.py`/`.rs`/`.ino`/…) |
| 8 | `devplan` | `docs/DEVPLAN.md` | ≥1 heading **plus** ≥1 content line |

Behaviour worth knowing before you diagnose anything:

- **Stage 4 self-scaffolds.** `bootstrapKicadProject` runs before *every* schematic
  attempt (not once), because a rollback's `git clean -fd` deletes the untracked scaffold
  An empty schematic on disk before a stage-4 attempt is expected, not a bug.
- **Stage 6 also emits a JLCPCB assembly BOM** deterministically, on the pass that
  completes it and on every later resume.
- **Stages 4, 5, 6 render SVG artifacts** into the run directory.
- **Resume is automatic.** Stages whose contract already holds are skipped and committed
  (`commitResumedStage`) — the same command resumes; there is no resume flag.
- **Per-stage auto-retry.** On failure the pipeline asks the model to `diagnose` and
  returns `retry` (re-runs with guidance prepended) or `abort`. Budget is
  `maxStageRetries` (default 2) → up to 3 attempts per stage.
- **Rollback is destructive to untracked files.** `restore()` = `git reset --hard` +
  `git clean -fd`, sparing `.copperhead/runs`. Work is stashed first by
  `preserveFailedRun` as `copperhead failed run <runId>` — recover with `git stash list`.

---

## 3. Preconditions

Run the whole block and paste the output at the top of the attempt log. Do not start a run
with any line unverified.

```bash
# 3.1 CLI resolves to the local dev build (not a stale global install)
readlink -f "$(which copperhead)"     # expect: .../copperhead/dist/cli.js
copperhead --version

# 3.2 Toolchain
node -v
kicad-cli --version                   # required for ERC/DRC/export stages

# 3.3 Workspace is a git repo with at least one commit  ← create refuses otherwise
git -C . rev-parse --is-inside-work-tree
git -C . log --oneline -1

# 3.4 Disk headroom: preflight refuses below 2 GiB
df -h .

# 3.5 Leak watch (I9) — recorded automatically by run-attempt.sh; this is the manual form
ls -d /tmp/copperhead-* 2>/dev/null | wc -l
du -sh .history 2>/dev/null || echo "no .history yet"
```

A workspace built by `bin/new-workspace.sh` is already a git repo with a baseline commit, so
`create` will not refuse on §3.3. Do **not** run `git init` in an existing workspace.
`bin/doctor.sh -w <workspace>` runs this whole block for you and fails on the same
conditions.

**Nothing that matters may be untracked.** §2's rollback is `git reset --hard` +
`git clean -fd -e .copperhead/runs`, so any untracked file in the workspace is destroyed by
the first stage failure. This is why the harness lives outside the workspace rather than
being gitignored inside it — an ignore entry survives `clean -fd` (no `-x`), but the design
agent's `search` does not respect `.gitignore`, and 6.6 MB of transcripts in the repo is
what caused the context overflow in I5.

If the CLI does not resolve to the dev build, or you changed copperhead source:

```bash
cd ../copperhead && npm run build && npm link
cd ../copperhead-test-harness/workspaces/<name> && npm link copperhead
readlink -f "$(which copperhead)"     # re-verify; do not assume the relink took
copperhead --version                  # and that it actually runs
```

`readlink` alone is not enough. A `dist/cli.js` that lost its executable bit still satisfies
the symlink while `which copperhead` returns nothing (I6) — check the version too, and
`bin/run-attempt.sh` refuses to start if either fails.

### 3.6 Knobs (record any deviation from default in the attempt log)

`create` accepts only `--brief`, `--model`, `--interactive`. There is **no
`--max-turns` on create** — turn budget goes through `.copperhead/config.json`:

| Setting | Default | Where |
| --- | --- | --- |
| `maxTurns` | 40 | `.copperhead/config.json` |
| `stageMaxTurns` | — | per-stage override, keyed by stage name |
| `maxStageRetries` | 2 | → 3 attempts per stage |
| `maxRepairCycles` | 5 | |
| `turnTimeoutMs` | 600000 (10 min) | per-turn watchdog; cumulative budget of 3 per stage |
| `heartbeatMs` | 30000 | distinguishes slow from hung |
| `llmCache` | true | `.copperhead/llm-cache/` — retries replay completed turns free |
| `COPPERHEAD_MIN_FREE_MB` | 2048 | env; lowers the disk preflight |
| `COPPERHEAD_MODEL` | — | env; alternative to `--model` |

---

## 4. Execution loop

### 4.1 Launch

One attempt at a time. Never run two attempts concurrently against the same workspace —
the temp sweep is age-gated at 2h and concurrent runs corrupt each other's git snapshots.

```bash
../copperhead-test-harness/bin/run-attempt.sh "the one variable changed vs the last attempt"
```

That is the whole launch procedure. The script verifies preconditions, refuses to start if
`copperhead` does not resolve *and run*, allocates the next `run-NN/` directory, captures
the real exit code (`PIPESTATUS[0]`, not `$?`, which under a pipe reports `tee`), copies the
evidence before anything can overwrite it, and writes `metadata.json`.

Do not hand-roll the capture. Three things went wrong when this was done by hand: `$?`
reported `tee`'s status, an evidence copy picked the wrong run directory because
`ls -1dt` ordered by a touched mtime, and one attempt ran against a `copperhead` that no
longer resolved.

### 4.1.1 What an attempt leaves behind

Attempts are grouped by **session** — one session per brief. Every rerun against the same
workspace and the same brief lands in the same session directory, named for when that
campaign started:

```text
run-logs/<session>/            e.g. 2026-07-31T23-32-26
  session.json                 brief identity, workspace, and the full attempt history
  attempt-NN/
    metadata.json              every field below, machine-readable
    create.log                 full terminal capture, stdout + stderr
    REPORT.md                  the human attempt report (§6) — you write this
    evidence/                  per-stage transcripts, git status/stash/log, disk, tmpdirs
    outputs/                   what the pipeline produced: docs/, outputs/, firmware/, KiCad files
```

The session is keyed on the brief's **content hash**, not its path: editing the brief
changes what is being tested, so it starts a new session rather than folding into the
previous campaign's history. Driving one brief to green is one directory, read top to
bottom.

`session.json` is rebuilt from the attempt directories on every run, so it cannot drift —
a hand-edited index is overwritten by the truth. It carries `best_stages_completed`
(how far this brief has ever got, across every attempt), `resolved`, and one row per
attempt with its outcome, the variable changed, and the copperhead sha it ran against.
That row list is the fastest read on whether a campaign is converging:

```bash
jq '.best_stages_completed, .history[] | {attempt, outcome, variable_changed, stages_completed}' \
   run-logs/<session>/session.json
```

`evidence/` is how the attempt failed; `outputs/` is what it produced. Keeping them apart
matters when comparing two attempts: a diff of `run-01/outputs/docs` against
`run-02/outputs/docs` shows what changed in the design, without the transcripts in the way.

`metadata.json` records, per attempt: outcome and exit code; the §1 definition of done
evaluated field by field; the variable changed; copperhead branch/HEAD/**dirty count** and
whether the run is reproducible from that sha; node and kicad-cli versions; workspace HEAD
before and after, commits landed, uncommitted count, stash entries; stages ran, resumed,
committed, and where it stopped; the per-stage cost table; turns, output tokens, wall,
cache-hit %; watchdog timeouts, provider errors, context overflows, stage retries,
rollbacks; disk and `/tmp/copperhead-*` before and after; and one entry per stage attempt
with its turn count, terminal outcome, and event-type histogram.

Compare attempts with `jq`, not by reading two logs:

```bash
cd ../copperhead-test-harness
jq -s '.[] | {attempt, outcome, stages: .stages.completed, cost: .cost, rel: .reliability}' \
   run-logs/<session>/attempt-*/metadata.json
```

### 4.2 One variable per attempt

Each attempt changes **exactly one** thing relative to the previous: one copperhead source
fix, or one config value, or one environment condition. An attempt that changes two things
cannot attribute the outcome to either. If you believe two fixes are both required, land
them as two attempts and say so.

Record, per attempt: the workspace HEAD, the copperhead HEAD, and the single variable
changed.

### 4.3 Loop

1. Run and capture (4.1).
2. Exit 0 **and** all five conditions in §1 → done. Report.
3. Otherwise → preserve evidence (§5.1) **before** touching anything.
4. Diagnose to a root cause with a named mechanism (§5.2). "It timed out" is a symptom,
   not a root cause.
5. Apply the smallest fix (§7). Prefer the local copperhead repo over the workspace.
6. Rebuild + relink + **re-verify the link** if source changed.
7. Rerun. Resume is automatic.

---

## 5. Failure handling

### 5.1 Evidence is already preserved

`run-attempt.sh` copies **every** `.copperhead/runs/*/` directory, the run report, and the
git/disk/tmp snapshots into `run-logs/<session>/attempt-NN/evidence/` before it exits — including on a
failure, and including when you interrupt it. There is nothing to do by hand.

Two things this replaced, both of which cost real evidence:

- Copying "the latest run directory" via `ls -1dt … | head -1` selected a *stage-1*
  transcript, because a later read had touched its mtime. The stage-4 transcripts that
  actually explained the failure were nearly lost. Copy them all; they are small.
- Evidence written inside the workspace is deleted by the next rollback (`git clean -fd`)
  and readable by the design agent (I5). It belongs outside the repo, which is where the
  script puts it.

If you interrupt an attempt before it exits, the evidence copy has not run. Recover it by
hand from `.copperhead/runs/` in the workspace — that directory is spared by `clean -fd`.

### 5.2 Read the transcript, not just the terminal

Each run writes `.copperhead/runs/<ISO-timestamp>/transcript.jsonl` (+ `summary.md`), and
the pipeline writes `.copperhead/runs/REPORT.md` and `report.json`. The JSONL is one
`{ts, type, data}` object per line. Grep by `type` — this is the fastest path to a root
cause:

```bash
RUN=$(ls -1dt .copperhead/runs/*/ | head -1)
jq -r '.type' "$RUN/transcript.jsonl" | sort | uniq -c | sort -rn      # shape of the run
jq -r 'select(.type|test("fail|refused|timeout|limit|restore")) | "\(.ts) \(.type) \(.data|tostring[0:300])"' \
   "$RUN/transcript.jsonl"
```

Event types the pipeline emits, and what each tells you:

| Event | Read it as |
| --- | --- |
| `run-start`, `run-end` | stage boundaries; the pair that's missing marks where it died |
| `turn-timeout` | watchdog fired. Cumulative budget of **3 per stage** — three independent slow turns fail a stage that was never hung |
| `session-limit`, `budget-extended` | turn budget exhausted; not a bug — a budget question |
| `run-failed`, `run-refused` | hard failure vs. the agent declining; different root causes |
| `restore-failed`, `work-preserved` | rollback path; `work-preserved` → check `git stash list` |
| `run-committed` | the stage's commit landed. Its absence after a green stage means the commit step failed |
| `provider-failover` | provider instability, not a copperhead defect |
| `tool` | every tool call; filter by tool name to find a looping repair cycle |
| `changelog-append-failed`, `synap-record-failed`, `openspec-archive-failed` | bookkeeping failures that can mask as stage failures |
| `edit-tools-unlocked`, `deferred-affects-reopened` | gate/obligation state changes |

### 5.3 Triage table

Match the observable signal to the mechanism before proposing a fix:

| Signal | Likely mechanism | First check |
| --- | --- | --- |
| Stage ran green but pipeline stopped | Completion contract unmet (`the stage completion contract is not met`) | Run the §2 contract for that stage by hand |
| `turn exceeded 600000ms` ×3 in one stage | cumulative watchdog budget | Were the turns *productive*? Large-output capture turns are slow, not hung |
| `ENOSPC` / commands failing mid-run | I9 — `/tmp/copperhead-*` + `.history/` growth | `df -h`, `ls -d /tmp/copperhead-*`, `du -sh .history` |
| Commit step fails | `git add -A` vs. KiCad's git-backed `.history/` | `git status --porcelain`, check `.gitignore` |
| Retry runs against a missing schematic | rollback wiped the untracked scaffold | Confirm re-scaffold line appears on attempt ≥2 |
| Drift never clears on stage 4 | drift checker misreading an auxiliary table | Inspect every table in `BOM.md`/`PINOUT.md` |
| ERC clean but the part is wrong | I4 — placeholder symbols carry no pin types | `verify_symbols`; compare against installed `.kicad_sym` |
| Token cost balloons on `claude-code` | I8/R7 — cache reports 0% | Compare `--model claude` (prompt caching active) |

Every failure analysis must answer, in the attempt report:

1. Which stage, which attempt number, which turn?
2. Mechanism: timeout / contract-unmet / tool defect / rollback / resource exhaustion /
   provider / budget?
3. Was work lost or left uncommitted? (`git stash list`, `git status`)
4. New, or a recurrence? Cite the issue ID and update its status flag if a recurrence.
5. What is the *smallest* change that would have prevented it?

---

## 6. Attempt report

Write one after **every** attempt, pass or fail, to `run-logs/<session>/attempt-NN/REPORT.md`. Another
engineer must be able to resume from it without re-reading the transcript.

Do **not** restate what `metadata.json` already holds — exit code, stage counts, turns,
tokens, cache, timeouts, commits, disk. Those are captured automatically and a hand-copied
number is one more thing that can be wrong. The report is for the judgement the metadata
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
<Log line refs, transcript event types, file:line in copperhead. Anything asserted here
must be checkable from ./evidence/ without re-running.>

## Root cause
<The defect, or environment / budget / provider. If the diagnosis is a guess, say so.>

## New or recurrence
<NEW → add to ISSUES-FOUND.md with a status flag | recurrence of I<n> → update that entry>

## Action taken
<The smallest fix, file:line and commit. Or "none — investigation only".>

## Validated
<Which run confirmed it, or "not yet — no run has passed this point since the fix".
A unit test is not validation (§8).>

## Next attempt
<The single variable to change.>
```

Every failure analysis must answer, somewhere in that report:

1. Which stage, which of its 3 attempts, which turn?
2. Mechanism: timeout / contract-unmet / tool defect / rollback / resource exhaustion /
   provider / budget / context overflow?
3. Was work lost or left uncommitted? (`evidence/git-stash.txt`, `evidence/git-status.txt`)
4. New, or a recurrence? Cite the issue ID.
5. What is the *smallest* change that would have prevented it?

---

## 7. Fixing copperhead

When the root cause is a copperhead defect:

1. **Reproduce it from the evidence**, not from memory — cite the log line and the
   transcript event.
2. **Locate it in source** and quote `file:line`.
3. **Write the smallest fix.** Prefer narrowing a condition over adding a code path;
   prefer a code path over a rewrite. If the fix needs a redesign, ship the narrow
   mitigation and open the redesign in `../run-logs/RECOMMENDATIONS.md` — do not do both
   in one attempt.
4. **Add a regression test** in `../copperhead/test/`. Use the failing run's real strings
   as fixtures — `test/draft-ir-bom.test.ts` and `test/draft-hardening.test.ts` are the
   pattern, and each case there carries a comment saying what it cost.
5. `cd ../copperhead && npm run build && npm test`, then relink and **re-verify** that
   `copperhead --version` runs (not just that the symlink resolves — I6).
6. **Mark it `FIXED`, not `VALIDATED`.** A fix is `VALIDATED` only by an attempt that gets
   past the point it was blocking. Say plainly when a rerun does not.
7. **Document it** (§8).

Open or update a GitHub issue with the evidence when the defect is real and not already
tracked. Cite the attempt directory — `run-logs/<session>/attempt-NN/` — so the evidence is findable.

### 7.1 Stop conditions

Stop and report a blocker — do not keep looping — when any of these is true:

- The **same mechanism** (not the same stage) recurs 3 times with no fix that advances
  the pipeline.
- A fix would require hand-editing workspace artifacts to satisfy a gate (§1.1).
- The failure is external and unfixable here: provider outage, missing `kicad-cli`,
  exhausted disk that cannot be freed.
- Two consecutive attempts reach a *strictly earlier* stage than their predecessor —
  the fixes are regressing, so stop and re-baseline.

Report a blocker with the same template as §6, plus what you tried and why each was
rejected.

---

## 8. Documentation rules

Document only **new** findings, grounded in observed evidence. No speculation.

Two registers, both carrying a status flag on every entry:

- **Defects** → [`run-logs/ISSUES-FOUND.md`](../run-logs/ISSUES-FOUND.md). Continue the `I<n>`
  numbering. Severity is `BLOCKER` · `DEFECT` · `INEFFICIENCY` · `NOTE`; status is `OPEN` ·
  `FIXED` · `VALIDATED` · `BY-CONTRACT` · `WONTFIX` · `INVALID`. The file defines each.
- **Improvements that are not defects** → [`run-logs/RECOMMENDATIONS.md`](../run-logs/RECOMMENDATIONS.md).
  `R<n>`, priority `P0`–`P3`, status `OPEN` · `DONE` · `PARTIAL` · `DECLINED` ·
  `SUPERSEDED`.

Rules for both:

- **Update the flag in place.** Never open a second entry for the same defect; never delete
  one that turned out to be wrong — mark it `INVALID` and say what was actually true. A
  wrong diagnosis that someone already spent an attempt on is worth more written down than
  erased.
- **The summary table at the top is part of the entry.** Change the detail and the table row
  together, or the register lies at a glance — which is the only way most people read it.
- **`FIXED` ≠ `VALIDATED`.** Landing a fix with a passing unit test earns `FIXED`. Only a
  run that gets past the blockage earns `VALIDATED`, and it must cite the run. This
  distinction is the entire point of the flag: a register full of `FIXED` with no
  `VALIDATED` is an honest statement that nothing has been proven end-to-end yet.
- **Every fix records** what changed (`file:line` and commit), why, which run and failure
  triggered it, whether a run has validated it, and what remains open.
- **`BY-CONTRACT` needs a location.** "Enforced in the stage-3 prompt" is a status; "handled
  elsewhere" is not.

---

## 9. Operating discipline

- Evidence before behaviour: `run-attempt.sh` captures it, but never rebuild or rerun before
  confirming the previous attempt's `evidence/` is populated.
- Smallest fix over broad rewrite. No speculative changes.
- One variable per attempt, recorded in `metadata.json`.
- Never satisfy a completion gate by hand to make a run go green.
- The CLI's exit code and the five conditions in §1 are the only success signal.
  `metadata.json` evaluates all five; read `definition_of_done` rather than eyeballing.
- Report faithfully: a partially-fixed run is a failed attempt that got further, not a pass.
- Keep the harness out of the workspace. Every doc and every log in this directory is
  invisible to the design agent, and that is load-bearing (I5, and the guide-as-design-input
  problem in §"Where things live").
- Keep the loop continuous until success or a §7.1 stop condition.
