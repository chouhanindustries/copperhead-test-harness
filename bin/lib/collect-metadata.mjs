/**
 * Build run-logs/<session>/attempt-NN/metadata.json: everything about one attempt, in one
 * machine-readable place.
 *
 * Most of it comes from the environment the runner already gathered. The rest
 * is derived by reading what the run left behind — the terminal log for the
 * cost table and stage transitions, the per-stage transcripts for the event
 * counts that explain *why* an attempt ended the way it did.
 *
 * Written so a later attempt can be compared to this one field by field: the
 * guide's discipline is one variable per attempt, and that is only checkable if
 * every other variable is recorded.
 */
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';

const env = process.env;
const RUN = env.RUNDIR;
const log = existsSync(env.LOGFILE) ? readFileSync(env.LOGFILE, 'utf8') : '';

const grab = (re, fallback = null) => {
  const m = re.exec(log);
  return m ? m[1].trim() : fallback;
};

/** Per-stage cost table the CLI prints at the end. */
function costTable() {
  const rows = [];
  const block = /Per-stage cost summary([\s\S]*?)(?:\n\s*\n|wrote run report|$)/.exec(log);
  if (!block) return rows;
  for (const line of block[1].split('\n')) {
    const m = /^\s{2}([a-z-]+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\d+)%\s*$/.exec(line);
    if (m) rows.push({ stage: m[1], wall: m[2], turns: Number(m[3]), output_tokens: m[4], cache_pct: Number(m[5]) });
  }
  return rows;
}

/** Event-type counts per stage transcript — the fastest read on how a run died. */
function transcripts() {
  const dir = path.join(RUN, 'evidence');
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((d) => statSync(path.join(dir, d)).isDirectory())
    .sort()
    .map((d) => {
      const f = path.join(dir, d, 'transcript.jsonl');
      if (!existsSync(f)) return { run_id: d, events: {} };
      const events = {};
      let turns = 0;
      for (const line of readFileSync(f, 'utf8').split('\n')) {
        if (!line.trim()) continue;
        let o;
        try {
          o = JSON.parse(line);
        } catch {
          continue;
        }
        events[o.type] = (events[o.type] ?? 0) + 1;
        if (o.type === 'assistant') turns++;
      }
      // The terminal outcome of this stage attempt, if it reached one.
      const outcome = ['run-refused', 'run-failed', 'run-committed'].find((k) => events[k]);
      return { run_id: d, turns, outcome: outcome ?? 'incomplete', events };
    });
}

const stagesSeen = [...log.matchAll(/^stage ([a-z-]+): running/gm)].map((m) => m[1]);
const stagesResumed = [...log.matchAll(/^stage ([a-z-]+): already complete/gm)].map((m) => m[1]);

/**
 * Commits this attempt landed, read from the workspace's own history
 * (evidence/git-log.txt) rather than the CLI's terminal output (I14): a SIGINT
 * pre-empts the CLI's commit lines, and their format has already drifted once
 * (`committed <sha> (N file(s))` vs the `<sha> copperhead: …` this script once
 * parsed). Commit subjects are the stable interface. Everything above the
 * pre-run HEAD is this attempt's.
 */
function commitsLanded() {
  const f = path.join(RUN, 'evidence/git-log.txt');
  if (!existsSync(f)) return { head: null, commits: [] };
  const lines = readFileSync(f, 'utf8').split('\n').filter(Boolean);
  const head = lines[0]?.split(' ')[0] ?? null;
  const before = env.WS_HEAD_BEFORE ?? '';
  const commits = [];
  for (const line of lines) {
    const sha = line.split(' ')[0] ?? '';
    if (before && (sha.startsWith(before) || before.startsWith(sha))) break;
    const m = /^([0-9a-f]{7,})\s+copperhead: create pipeline stage: ([a-z-]+)/.exec(line);
    if (m) commits.push({ sha: m[1], stage: m[2] });
  }
  return { head, commits: commits.reverse() }; // oldest first, matching run order
}
const landed = commitsLanded();
const committed = landed.commits;
// A retried stage commits more than once; completion is counted in stages, not commits.
const stagesCommitted = new Set(committed.map((c) => c.stage));
const cost = costTable();
const totals = /^\s{2}TOTAL\s+(\S+)\s+(\d+)\s+(\S+)\s+(\d+)%/m.exec(log);
const exitCode = Number(env.EXIT ?? 1);
const complete = /create pipeline complete/.test(log);
const allGreen = /create pipeline complete; all checks green/.test(log);

const meta = {
  session: env.SESSION ? path.basename(env.SESSION) : null,
  attempt: env.ATTEMPT,
  outcome: exitCode === 0 && allGreen ? 'PASS' : exitCode === 0 && complete ? 'COMPLETE_WITH_CHECK_FAILURES' : 'FAIL',
  exit_code: exitCode,
  // The guide's definition of done, evaluated field by field rather than asserted.
  definition_of_done: {
    exited_zero: exitCode === 0,
    all_stages_complete: complete,
    checks_green: allGreen,
    every_stage_committed: committed.length > 0 && stagesCommitted.size >= new Set(stagesSeen).size,
    artifacts_preserved: existsSync(path.join(RUN, 'evidence', 'report.json')),
  },
  command: `copperhead create --brief ${env.BRIEF ?? 'brief.md'} --model claude-code`,
  workspace_path: env.WORKSPACE_PATH ?? null,
  variable_changed: env.VARIABLE,
  timing: { started: env.STARTED, ended: env.ENDED, elapsed_s: Number(env.ELAPSED ?? 0), wall: totals?.[1] ?? null },
  copperhead: {
    bin: env.CH_BIN,
    version: env.CH_VERSION,
    branch: env.CH_BRANCH,
    head: env.CH_HEAD,
    dirty_files: Number(env.CH_DIRTY ?? 0),
    // A dirty tree means the binary under test exists in no commit: this sha
    // will not reproduce this run.
    reproducible_from_head: Number(env.CH_DIRTY ?? 0) === 0,
  },
  toolchain: { node: env.NODE_V, kicad_cli: env.KICAD_V },
  workspace: {
    head_before: env.WS_HEAD_BEFORE,
    head_after: landed.head ?? env.WS_HEAD_BEFORE,
    commits_landed: committed,
    uncommitted_at_exit: existsSync(path.join(RUN, 'evidence/git-status.txt'))
      ? readFileSync(path.join(RUN, 'evidence/git-status.txt'), 'utf8').split('\n').filter(Boolean).length
      : null,
    stash_entries: existsSync(path.join(RUN, 'evidence/git-stash.txt'))
      ? readFileSync(path.join(RUN, 'evidence/git-stash.txt'), 'utf8').split('\n').filter(Boolean).length
      : null,
  },
  stages: {
    total: 8,
    completed: stagesCommitted.size,
    resumed: stagesResumed,
    ran: stagesSeen,
    stopped_in: grab(/stopped at stage \d+\/8 \(([a-z-]+)\)/) ?? stagesSeen.at(-1) ?? null,
    per_stage: cost,
  },
  cost: {
    turns: totals ? Number(totals[2]) : cost.reduce((a, r) => a + r.turns, 0),
    output_tokens_h: totals?.[3] ?? null,
    wall: totals?.[1] ?? null,
    cache_hit_pct: totals ? Number(totals[4]) : null,
  },
  reliability: {
    watchdog_timeouts: (log.match(/turn exceeded \d+ms/g) ?? []).length,
    provider_errors: (log.match(/provider error:/g) ?? []).length,
    context_overflows: (log.match(/Prompt is too long/g) ?? []).length,
    stage_retries: (log.match(/running \(attempt \d+\/\d+\)/g) ?? []).length,
    rollbacks: (log.match(/working tree restored/g) ?? []).length,
  },
  resources: {
    disk_free_before: env.DISK_BEFORE,
    disk_free_after: (/\s(\S+)\s+\d+%/.exec(
      existsSync(path.join(RUN, 'evidence/disk.txt'))
        ? readFileSync(path.join(RUN, 'evidence/disk.txt'), 'utf8').split('\n')[1] ?? ''
        : '',
    ) ?? [])[1] ?? null,
    tmpdirs_before: Number(env.TMP_BEFORE ?? 0),
    tmpdirs_after: existsSync(path.join(RUN, 'evidence/tmpdirs.txt'))
      ? readFileSync(path.join(RUN, 'evidence/tmpdirs.txt'), 'utf8').split('\n').filter(Boolean).length
      : null,
  },
  stage_attempts: transcripts(),
  paths: { dir: RUN, log: env.LOGFILE, evidence: path.join(RUN, 'evidence'), outputs: path.join(RUN, 'outputs') },
};

writeFileSync(env.COPPERHEAD_RUN_META, JSON.stringify(meta, null, 2) + '\n', 'utf8');
