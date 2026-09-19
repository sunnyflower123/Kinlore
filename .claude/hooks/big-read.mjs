#!/usr/bin/env node
// Block a whole-file read of a large file, and say what to do instead.
//
// Measured 19 Sep 2026 over the fifty session transcripts in
// ~/.claude/projects/: 72 of 2041 file-reading calls were over 350 lines —
// 3.5% of the calls carrying 492,000 tokens, 28% of everything read. What a
// session reads is re-sent on every later turn (a measured 68 cache reads per
// cache write), so those 72 calls are the ones worth stopping. The other 1969
// are small and targeted and pass untouched.
//
// Fails open. A hook that cannot decide must not stop the work: every error
// path exits 0, and the read happens.

import fs from 'node:fs';

const LIMIT = Number(process.env.KINLORE_MAX_READ_LINES || 350);
const allow = () => process.exit(0);

const deny = (reason) => {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0);
};

// Whole-file readers. head/tail without an explicit count show ten lines, so
// they are targeted and are not listed here.
const DUMPERS = /(?:^|[;&]|\|\||&&)\s*(?:cat|less|more|bat)\s+([^|;&<>]+)/;
const COUNTED = /(?:^|[;&]|\|\||&&)\s*(?:head|tail)\s+(?:-n\s*(\d+)|-(\d+))\s+([^|;&<>]+)/;
const BINARY = /\.(png|jpe?g|gif|webp|heic|pdf|mp4|mov|m4a|wav|zip|sqlite|db|ico|icns|ttf|otf)$/i;

const lineCount = (p) => {
  const st = fs.statSync(p);
  if (!st.isFile()) return 0;
  // Bytes first: nothing under 350 bytes can be over 350 lines.
  if (st.size < LIMIT) return 0;
  return fs.readFileSync(p, 'utf8').split('\n').length;
};

const advice = (what, n) =>
  `${what} is ${n} lines. Reading it whole puts all of it in this session's ` +
  `context, where it is re-sent on every later turn. Either read the part you ` +
  `need (Read with offset/limit, or grep/sed -n), or — if the answer needs the ` +
  `whole file, or several files, and only the conclusion matters — hand it to ` +
  `the bulk-reader subagent, which reads in its own context and returns ` +
  `path:line facts. Set KINLORE_MAX_READ_LINES to raise the ${LIMIT}-line ` +
  `threshold if this file really must be read whole.`;

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  let ev;
  try { ev = JSON.parse(input); } catch { allow(); }

  // A subagent's context is thrown away when it returns, so there is nothing
  // in it to protect — and blocking it would break the very delegation this
  // hook recommends.
  if (ev.agent_id || ev.agent_type) allow();

  try {
    if (ev.tool_name === 'Read') {
      const i = ev.tool_input || {};
      if (i.offset || i.limit || i.pages) allow();          // already targeted
      const p = i.file_path || '';
      if (!p || BINARY.test(p)) allow();
      const n = lineCount(p);
      if (n > LIMIT) deny(advice(p, n));
      allow();
    }

    if (ev.tool_name === 'Bash') {
      const cmd = (ev.tool_input || {}).command || '';
      // A pipe or a redirect means the output is filtered or goes to a file,
      // so almost none of it reaches the context. 799 of the 1330 measured
      // cat/head/tail calls were piped; blocking those would be 799 wrong
      // answers for nothing.
      if (/[|>]/.test(cmd)) allow();
      let m = DUMPERS.exec(cmd);
      let files = null, asked = Infinity;
      if (m) {
        files = m[1];
      } else if ((m = COUNTED.exec(cmd))) {
        asked = Number(m[1] || m[2]);
        files = m[3];
        if (asked <= LIMIT) allow();
      }
      if (!files) allow();
      for (const tok of files.trim().split(/\s+/)) {
        if (tok.startsWith('-') || BINARY.test(tok)) continue;
        const n = lineCount(tok);
        if (n > LIMIT && Math.min(n, asked) > LIMIT) deny(advice(tok, n));
      }
      allow();
    }
  } catch { allow(); }
  allow();
});
