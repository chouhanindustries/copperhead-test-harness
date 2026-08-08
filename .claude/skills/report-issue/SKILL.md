---
name: report-issue
description: File an upstream copperhead issue from an attempt's evidence, or update an existing one on a recurrence. Use after diagnosing a run — e.g. /report-issue I20, "file this upstream", "open an issue for the stage-4 refusal".
allowed-tools: AskUserQuestion, Bash(gh:*), Bash(git:*), Bash(jq:*), Bash(node:*), Bash(ls:*), Read, Grep, Glob, Edit
compatibility: Requires the gh CLI authenticated against chouhanindustries/copperhead.
metadata:
  author: copperhead-test-harness
  version: "1.0"
---

Turn a diagnosed attempt failure into an upstream issue on
`chouhanindustries/copperhead`, with evidence another engineer can check without access to
this machine.

The local register (`run-logs/ISSUES-FOUND.md`) and the upstream tracker serve different
readers: the register is this campaign's memory, the issue is how a fix gets made. File
upstream when the defect is real, reproducible from evidence, and lives in copperhead —
not when it is an environment problem, a budget question, or a provider outage.

## Before filing

1. **Diagnose first.** This skill files what `attempt-report` diagnosed. If there is no
   `REPORT.md` with a named mechanism, write it first — an issue whose mechanism is "it
   timed out" wastes a maintainer's day.
2. **Check the local register.** If the mechanism already carries an `I<n>`, this is a
   recurrence: update that entry's status and comment on the existing upstream issue rather
   than opening a second one.
3. **Search upstream.** Recurrences and near-duplicates are common in this pipeline.
   ```bash
   gh issue list --repo chouhanindustries/copperhead --state all --search "<mechanism keywords>" --limit 20
   ```
   If a match exists, comment on it with the new evidence and stop.
4. **Confirm it is copperhead's.** A reduced KiCad symbol library set, an unfreeable disk,
   or a stale `dist/` produce failures that read as defects. Rule those out — `bin/doctor.sh`
   covers each — before blaming the CLI.
5. **Ask before posting.** Show the user the rendered title and body and get an explicit go.
   Filing is public and outward-facing.

## The issue

Title states the mechanism and its consequence, not the symptom. Match the register's
house style — long, specific, and readable on its own:

> Symbol resolution offers no cross-library discovery: `Sensor_Energy:INA226` missed after 7 wrong-library probes, blocking stage 4 on three briefs

Body, following the repo's bug-report template:

```markdown
## What happened
<Expected versus observed, in two or three sentences. Name the stage and the mechanism.>

## Steps to reproduce
1. `copperhead create --brief brief.md --model claude-code:opus` in a workspace whose
   `docs/BOM.md` contains <the specific condition>
2. <what the run does>
3. <where it stops>

Brief: `briefs/<name>.md` in the harness, if the brief is what triggers it.

## Output
```
<Log lines and transcript events, quoted exactly. Scrub credentials and absolute home
paths. Prefer the smallest excerpt that shows the mechanism over a full dump.>
```

## Root cause
<`file:line` in copperhead where you can point at it. If the diagnosis is a hypothesis,
say so plainly — a wrong confident diagnosis costs more than an honest uncertain one.>

## Impact
<How many briefs or stages this blocked, from the evidence. "Blocked stage 4 on all three
briefs in the 2026-08-04 batch" is worth more than "high severity".>

Which command: create
Model backend: Claude Code saved login
copperhead version: <version> (<branch> @ <sha>)
Node, KiCad, OS: <node -v>, <kicad-cli --version>, <os>
```

Pull the version, branch, sha, node and kicad-cli lines from the attempt's
`metadata.json` — they are recorded per attempt precisely so an issue does not have to
guess what it ran against.

Do not paste absolute paths from this machine, and do not link to `run-logs/` — it is not
tracked, so the link resolves for nobody else. Quote the evidence inline instead.

## Filing

```bash
gh issue create --repo chouhanindustries/copperhead \
  --title "<mechanism and consequence>" \
  --body-file <path> \
  --label bug --label area:pipeline
```

Labels in use: `bug` · `enhancement` · `chore` · `documentation`, plus one area —
`area:pipeline` (create/do behaviour) · `area:integrations` (MCP, part research, providers)
· `area:observability` (run metadata, transcripts, agent loop) · `area:bom-export` ·
`area:fab-gate` · `area:ci`. Pick `enhancement` when the behaviour is correct as designed
and the ask is for it to be better — that is the same line `RECOMMENDATIONS.md` draws
against `ISSUES-FOUND.md`.

## Afterwards

Record the issue number in the register entry and in the attempt's `REPORT.md`, so the
local finding and the upstream thread point at each other. On a later attempt that gets
past the blockage, comment on the issue with the validating run and move the register entry
to `VALIDATED` — a fix nobody confirmed upstream gets re-broken.

Do not close, label beyond the above, or assign issues you did not open; those are state
changes for the maintainers.
