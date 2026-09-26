// Test fixture for workers.yaml — run with `semgrep --test`, gated by selftest.
// Deliberately vulnerable scanner test data: never execute or copy into a project.
// `ruleid:` = a finding is expected on the next line; `ok:` = none is.

const id = new URL(request.url).searchParams.get('id');
const SELECT_USER = 'SELECT * FROM users WHERE id = ?';

// --- artemis-js-d1-sql-interpolation ---------------------------------------------------

// ruleid: artemis-js-d1-sql-interpolation
db.prepare(`SELECT * FROM users WHERE id = ${id}`);
// ruleid: artemis-js-d1-sql-interpolation
env.DB.prepare(`DELETE FROM sessions WHERE token = ${id}`);
// ruleid: artemis-js-d1-sql-interpolation
db.prepare('SELECT * FROM users WHERE id = ' + id);

// A placeholder plus .bind() is the whole point of the prepared-statement API.
// ok: artemis-js-d1-sql-interpolation
db.prepare('SELECT * FROM users WHERE id = ?').bind(id);
// A template literal with no substitution is a constant string.
// ok: artemis-js-d1-sql-interpolation
db.prepare(`SELECT count(*) FROM users`);
// A query held in a constant is the CORRECT pattern and must never be flagged — a rule that
// fired here would be turned off within a week.
// ok: artemis-js-d1-sql-interpolation
db.prepare(SELECT_USER).bind(id);

// --- artemis-js-log-whole-env ----------------------------------------------------------

// ruleid: artemis-js-log-whole-env
console.log(env);
// ruleid: artemis-js-log-whole-env
console.error('startup failed', env);
// ruleid: artemis-js-log-whole-env
console.log(JSON.stringify(env));

// Named non-secret fields are what a log line is supposed to carry.
// ok: artemis-js-log-whole-env
console.log(env.PROJECT_VERSION);
// ok: artemis-js-log-whole-env
console.log({ version: env.PROJECT_VERSION, route: '/healthz' });
// Spreading env into a plain object is what the template's own handler does, and it is not
// a disclosure. Flagging it would fail the code this repo ships.
// ok: artemis-js-log-whole-env
const forwarded = { ...env, PROJECT_VERSION: 'dev' };

// --- artemis-js-math-random-secret -----------------------------------------------------

// ruleid: artemis-js-math-random-secret
const sessionToken = Math.random().toString(36);
// ruleid: artemis-js-math-random-secret
let csrfNonce = Math.random();
// ruleid: artemis-js-math-random-secret
const apiKey = Math.random().toString(16);

// Jitter, sampling and retry delays are the ordinary use and vastly more common.
// ok: artemis-js-math-random-secret
const jitterMs = Math.random() * 1000;
// ok: artemis-js-math-random-secret
const sampleRate = Math.random();
// The runtime ships a CSPRNG, and the template already uses it for the request id.
// ok: artemis-js-math-random-secret
const requestId = crypto.randomUUID();
