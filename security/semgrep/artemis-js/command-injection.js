// Test fixture for command-injection.yaml — run with `semgrep --test`, gated by selftest.
// Deliberately vulnerable code: never executed, never shipped, and platform does not scan
// itself. `ruleid:` = a finding is expected on the next line; `ok:` = none is.

import { exec, execSync } from 'node:child_process';
import * as cp from 'node:child_process';

const userInput = process.argv[2];

// Regression: semgrep resolves a bare "child_process" specifier back to the qualified
// child_process.exec() form, but it does NOT resolve the "node:"-prefixed specifier —
// which is the style this org writes. Every call below was silently missed before.
// ruleid: artemis-js-child-process-exec
exec(userInput);
// ruleid: artemis-js-child-process-exec
execSync(userInput);
// ruleid: artemis-js-child-process-exec
cp.exec(userInput);
// ruleid: artemis-js-child-process-exec
cp.execSync(userInput);

// A literal command carries no injection risk.
// ok: artemis-js-child-process-exec
exec('ls -la');
// ok: artemis-js-child-process-exec
cp.exec('ls -la');

// A regex .exec() is not a shell call and must never be flagged.
const pattern = /foo/;
// ok: artemis-js-child-process-exec
pattern.exec(userInput);

// ruleid: artemis-js-eval-nonliteral
eval(userInput);
// ok: artemis-js-eval-nonliteral
eval('1 + 1');
