/**
 * Rewrite `<session>/session.json` from what is actually on disk.
 *
 * A session is one brief driven toward a clean run. Its directory is named for
 * when that campaign started, and every attempt against the same workspace and
 * the same brief lands inside it — so the arc of a brief (what blocked it, what
 * was changed between attempts, whether it is converging) reads in one place
 * rather than being scattered across sibling directories.
 *
 * Rebuilt from the attempt directories on every run rather than appended to,
 * so it cannot drift from reality: an attempt deleted by hand disappears from
 * the index, and a hand-edited index is overwritten by the truth.
 */
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';

const SESSION = process.env.SESSION;
const attempts = readdirSync(SESSION)
  .filter((d) => /^attempt-\d+$/.test(d) && statSync(path.join(SESSION, d)).isDirectory())
  .sort();

const rows = attempts.map((dir) => {
  const f = path.join(SESSION, dir, 'metadata.json');
  if (!existsSync(f)) return { attempt: dir, status: 'no metadata (interrupted before it was written)' };
  const m = JSON.parse(readFileSync(f, 'utf8'));
  return {
    attempt: dir,
    outcome: m.outcome,
    exit_code: m.exit_code,
    started: m.timing?.started ?? null,
    variable_changed: m.variable_changed,
    copperhead: `${m.copperhead?.head}${m.copperhead?.dirty_files ? ` +${m.copperhead.dirty_files} dirty` : ''}`,
    stages_completed: m.stages?.completed ?? null,
    stopped_in: m.stages?.stopped_in ?? null,
    turns: m.cost?.turns ?? null,
    output_tokens: m.cost?.output_tokens_h ?? null,
    wall: m.cost?.wall ?? null,
  };
});

const best = rows.reduce((a, r) => Math.max(a, r.stages_completed ?? 0), 0);
const brief = path.join(process.env.WORKSPACE, process.env.BRIEF);

const session = {
  session: path.basename(SESSION),
  brief: {
    path: process.env.BRIEF,
    sha: process.env.BRIEF_SHA,
    // First line of the brief: enough to tell two sessions apart at a glance.
    title: existsSync(brief) ? (readFileSync(brief, 'utf8').split('\n').find((l) => l.trim()) ?? '').slice(0, 120) : null,
  },
  workspace: process.env.WORKSPACE,
  attempts: rows.length,
  // How far this brief has ever got, across every attempt. The number that says
  // whether the campaign is converging.
  best_stages_completed: best,
  resolved: rows.some((r) => r.outcome === 'PASS'),
  history: rows,
};

writeFileSync(path.join(SESSION, 'session.json'), JSON.stringify(session, null, 2) + '\n', 'utf8');
