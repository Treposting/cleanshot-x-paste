// Keeps issues up to date as work on them moves along. Used by actions/github-script.
//
// push:    a commit that mentions #N on a work branch → "Work has started", label `in progress`.
//          "Fixes #N" (or closes/resolves) landing on the default branch → "Fixed", label
//          `fixed (unreleased)`. Every mentioning commit is listed in one status comment.
// release: every issue labelled `fixed (unreleased)` gets "Released in vX", label `released`,
//          and is closed.
//
// Milestones get their own comment (so people watching the issue are notified); the
// commit log lives in a single status comment that is edited in place.

const MARKER = '<!-- marquee-issue-status -->';
const FOOTER = '<sub>Updated automatically from commits and releases.</sub>';
const LABELS = {
  progress: { name: 'in progress', color: 'FBCA04', description: 'Someone is working on this' },
  fixed: { name: 'fixed (unreleased)', color: '0E8A16', description: 'Fixed on main; ships in the next release' },
  released: { name: 'released', color: '1D76DB', description: 'The fix is in a published release' },
};
const HEADERS = {
  progress: '🛠 **In progress**',
  fixed: '✅ **Fixed**, ships in the next release',
  released: '🚀 **Released**',
};

module.exports = async ({ github, context, core }, mode, opts = {}) => {
  const { owner, repo } = context.repo;

  const ensureLabels = async () => {
    for (const l of Object.values(LABELS)) {
      try { await github.rest.issues.getLabel({ owner, repo, name: l.name }); }
      catch { await github.rest.issues.createLabel({ owner, repo, ...l }).catch(() => {}); }
    }
  };

  const findStatus = async (number) => {
    const comments = await github.paginate(github.rest.issues.listComments, { owner, repo, issue_number: number, per_page: 100 });
    return comments.find((c) => c.body && c.body.includes(MARKER));
  };

  const writeStatus = async (number, state, newLines) => {
    const existing = await findStatus(number);
    const log = existing ? (existing.body.split('\n### Activity\n')[1] || '').replace(FOOTER, '').trim() : '';
    const body = [
      MARKER,
      `**Status:** ${HEADERS[state]}`,
      '',
      '### Activity',
      [log, ...newLines].filter(Boolean).join('\n'),
      '',
      FOOTER,
    ].join('\n');
    if (existing) await github.rest.issues.updateComment({ owner, repo, comment_id: existing.id, body });
    else await github.rest.issues.createComment({ owner, repo, issue_number: number, body });
  };

  const setLabel = async (number, add, current) => {
    for (const key of Object.keys(LABELS)) {
      const name = LABELS[key].name;
      if (key !== add && current.includes(name)) {
        await github.rest.issues.removeLabel({ owner, repo, issue_number: number, name }).catch(() => {});
      }
    }
    if (!current.includes(LABELS[add].name)) {
      await github.rest.issues.addLabels({ owner, repo, issue_number: number, labels: [LABELS[add].name] });
    }
  };

  const today = () => new Date().toISOString().slice(0, 10);

  if (mode === 'push') {
    const branch = context.ref.replace('refs/heads/', '');
    const onMain = branch === context.payload.repository.default_branch;
    const mention = /(?<![\w&/])#(\d+)\b/g;
    const fixing = /\b(?:fix(?:e[sd])?|close[sd]?|resolve[sd]?)\s*:?\s+#(\d+)\b/gi;

    const byIssue = new Map();
    for (const c of context.payload.commits || []) {
      const msg = c.message || '';
      const fixes = new Set([...msg.matchAll(fixing)].map((m) => +m[1]));
      for (const m of msg.matchAll(mention)) {
        const n = +m[1];
        const entry = byIssue.get(n) || { commits: [], fixes: false };
        if (!entry.commits.some((x) => x.id === c.id)) entry.commits.push(c);
        if (fixes.has(n)) entry.fixes = true;
        byIssue.set(n, entry);
      }
    }
    if (!byIssue.size) { core.info('No issue references in this push.'); return; }
    await ensureLabels();

    for (const [number, { commits, fixes }] of byIssue) {
      let issue;
      try { ({ data: issue } = await github.rest.issues.get({ owner, repo, issue_number: number })); }
      catch { core.info(`#${number} is not an issue here; skipping.`); continue; }
      if (issue.pull_request) continue;

      const labels = issue.labels.map((l) => (typeof l === 'string' ? l : l.name));
      const lines = commits.map((c) =>
        `- ${today()}: [\`${c.id.slice(0, 7)}\`](${c.url}) ${c.message.split('\n')[0]} (on \`${branch}\`)`);

      if (fixes && onMain) {
        if (!labels.includes(LABELS.fixed.name) && !labels.includes(LABELS.released.name)) {
          await github.rest.issues.createComment({ owner, repo, issue_number: number, body:
            `✅ A fix for this is now on \`${branch}\` (${commits.map((c) => `\`${c.id.slice(0, 7)}\``).join(', ')}). ` +
            `It ships in the next release, and this issue will be updated when it's out.` });
        }
        await setLabel(number, 'fixed', labels);
        await writeStatus(number, 'fixed', lines);
      } else {
        const state = labels.includes(LABELS.fixed.name) ? 'fixed' : 'progress';
        if (state === 'progress' && !labels.includes(LABELS.progress.name)) {
          await github.rest.issues.createComment({ owner, repo, issue_number: number, body:
            `🛠 Work on this has started on \`${branch}\`. Progress is tracked in the status comment below.` });
          await setLabel(number, 'progress', labels);
        }
        await writeStatus(number, state, lines);
      }
    }
    return;
  }

  if (mode === 'release') {
    const { version, url } = opts;
    await ensureLabels();
    const issues = await github.paginate(github.rest.issues.listForRepo, {
      owner, repo, state: 'all', labels: LABELS.fixed.name, per_page: 100,
    });
    for (const issue of issues) {
      if (issue.pull_request) continue;
      const labels = issue.labels.map((l) => (typeof l === 'string' ? l : l.name));
      await github.rest.issues.createComment({ owner, repo, issue_number: issue.number, body:
        `🚀 The fix is in **Marquee ${version}**. Update with **Check for Updates…** in the menu bar, ` +
        `or download it from [the release page](${url}). If it still happens, reply here and we'll reopen it.` });
      await setLabel(issue.number, 'released', labels);
      await writeStatus(issue.number, 'released', [`- ${today()}: released in [${version}](${url})`]);
      if (issue.state === 'open') {
        await github.rest.issues.update({ owner, repo, issue_number: issue.number, state: 'closed', state_reason: 'completed' });
      }
    }
    core.info(`Updated ${issues.length} issue(s) for ${version}.`);
  }
};
