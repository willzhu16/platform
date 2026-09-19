# The testing standard

Why this exists: **the gate matrix is the reviewer** (D-04). There is one person on this
fleet and no second human to read a diff, so "reviewed" has to mean "a machine proved it",
not "someone looked at it and felt fine". Everything below is written to make that true, and
to be honest about where it stops being true.

Agents receive the short form of this through athena's `00-universal.md`, which links here.

## The order of work

1. **Write down what done means, before starting.** In the task packet, as numbered
   criteria. See "Criteria carry ids" below.
2. **Write the test, and watch it fail.** A test written after the code records what the
   code does, not what it should do. For a bug it must fail for the right reason first.
3. **Write the code until the test passes.**
4. **Check the gates.** They are listed below and they all run on the pull request.

## Criteria carry ids

This is the one habit the whole thing rests on, and the only part a person has to remember.

Write each acceptance criterion with a stable id:

```
- AC-1: an expired token is rejected with a 401 rather than a 500
- AC-2: the retry stops after three attempts
```

A test claims a criterion by naming it, in whatever spelling the language allows:

```ts
it('AC-1: rejects an expired token with a 401', () => { ... });
```

```python
def test_ac_1_rejects_an_expired_token(): ...
```

Python function names cannot contain `-` or `:`, so the claim is spelled as an identifier.
One concept, two spellings, each idiomatic where it is used.

The separator after the number is what distinguishes a claim from a mention, so a test
*discussing* AC-10 is not counted as covering it. An id inside a longer word claims nothing
either — `test_mac_10_address` is not evidence for AC-10. In TypeScript the id may sit on the
`it` or on a `describe` wrapping several tests; in Python it can be on the test function or
its module.

The `acceptance` check then fails the build for any criterion with no passing test, any
criterion whose only tests fail, any test claiming an id the packet does not list, any
reused id, and any packet with no criteria at all.

**A criterion that can only be checked by hand gets no id.** Leave it off deliberately and
say in the pull request how you checked it. A gate that silently counts manual criteria as
covered is worse than no gate, because it reports confidence it never earned.

## The gates, and what each one is for

| Gate | Answers |
|---|---|
| `lint` | Is it written the way this fleet writes code? |
| `typecheck` | Do the types hold? |
| `test` | Do the tests pass? |
| coverage floor | Did the tests at least *run* the code? |
| diff coverage | Are the lines **this pull request changed** covered? |
| `mutation` | Would a test have **noticed** if the code were wrong? |
| `acceptance` | Does every criterion someone wrote down have a passing test? |
| `security` | Secrets, known-vulnerable dependencies, dangerous patterns. |
| smoke | Does the **deployed** thing work, not just the code? |

The two that are easy to confuse:

**Coverage is the weak one.** It proves a line executed. A test that runs a line and
asserts nothing scores the same as one that checks the answer.

**Whole-repo coverage hides new code.** Add three hundred untested lines to a large repo
and the total barely moves — the number stays green while the thing you just wrote is
untested. Diff coverage asks the sharper question: of the lines this pull request touched,
how many are covered. It runs inside `ci / test`, so it needs no separate required check
and cannot be skipped by a repo that never adds one to its ruleset. A project that emits no
cobertura report skips it with a notice rather than failing.

**Mutation testing is the strong one.** It rewrites the source many ways — flips a
comparison, empties a string, deletes a branch — and reports how many of those edits broke
a test. It is the difference between checking a smoke alarm's light is on and holding a
match under it. It caught `doctor.ts`, the drift checker, sitting at 48% while every test
was green: it could have been rewritten to report a missing permission profile as a pass.

**Smoke is the one that does not trust any of the others.** Everything else runs against
source. Smoke runs against the deployed URL, because security headers arriving at a real
client depend on the wrangler config and the routing, which no unit test sees.

## Floors are measured, then ratcheted

Every threshold in this fleet — coverage, mutation score — was obtained by running
something and then set a few points under it.

- **Raise a floor when the number rises.** That is the ratchet.
- **Never lower one to turn a red build green.** Add the missing test instead.
- Re-baselining is allowed when a repo grows real code and the scaffolding's numbers stop
  being meaningful. Do it as a deliberate edit that shows up in a diff, with the new
  measurement in the commit message. Never as a reflex.
- Re-derive the number by running the tool. Never edit a stale figure to match a guess.

## When a branch genuinely cannot be tested

Say so at the site, in a comment, and file it. Do not leave a silent hole, and do not force
a contrived test that passes without proving anything.

The Worker template's error path was an example: covering it looked impossible, the note
said so, and on a second look it needed one injectable parameter. Writing the limitation
down is what made it fixable later.

## What these gates do not catch

Being clear about this is what keeps the rest trustworthy.

- **Wrong requirements.** If the criteria describe the wrong product, every gate goes green
  on the wrong thing. This is why the criteria are written by a person, before the work.
- **Tests that encode the same misunderstanding as the code.** When one author writes both,
  they can be wrong together. Mutation testing proves a test is *sensitive*; it cannot
  prove it asserts the *right* thing. The defence is that criteria come from outside the
  implementation.
- **Architecture and taste.** No gate will tell you a design will be painful in six months.
- **Whether the thing is worth building.**

Everything on that list is a reason to spend review effort on the packet, not the diff.
