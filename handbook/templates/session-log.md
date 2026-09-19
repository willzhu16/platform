# Session log

The last block of **every agent PR description** (athena spec 04 §2.6). It is the raw
material the monthly [session-log harvest](../cadences.md) turns into lint rules — so
write the dead ends down honestly; a clean-looking log with the struggle hidden starves
the flywheel.

The first six fields are enumerated so a program can tally them. The last three stay prose,
because the dead ends are the valuable part and no schema captures them. Until these fields
existed the harvest meant reading every PR by hand, which is why it kept not happening.

`bash scripts/session-log.sh < pr-body.md` validates a block. It needs bash and nothing
else, so it runs wherever a PR is reviewed.

Paste this at the bottom of the PR body and fill it. One field per line:

```
## Session log
Tool/model: <tool>/<model>
Packet: #<issue>, or none
Plan: before-first-edit | mid-task | none
Gates: <the gates you actually ran>
Retries: <N> gate failures before green
Abstained: no, or yes — <what you stopped and asked about>
Tried: <the approach that worked, in one line>
Dead ends: <what was attempted and abandoned, and why — this is the valuable part>
Decisions and why: <choices not spelled out in the packet, with the reason>
```

## Example

A filled log. CI validates this block on every platform PR, so the template and the
validator cannot drift apart:

```
## Session log
Tool/model: claude/opus-5
Packet: #42
Plan: before-first-edit
Gates: lint typecheck test mutation acceptance
Retries: 2 gate failures before green
Abstained: no
Tried: scoped the import ban to src/ with a biome override and proved it by rule name
Dead ends: asserted on the lint exit code first, which a stray formatting error also
  satisfies, so the probe would have passed without the rule firing at all
Decisions and why: listed bare specifiers beside the node: patterns rather than relying on
  useNodejsImportProtocol, so the rule does not depend on another rule staying enabled
```

## What each field is for

- **Plan** — whether a plan existed before the first edit, or arrived after the work was
  already underway. An agent that plans only after its first three edits is a different
  risk profile from one that plans first, and nothing else in the harness records it.
- **Gates** — which gates actually ran, not which exist. "All green" in a PR body has
  never distinguished "ran everything" from "ran what was fast".
- **Retries** — how many times a gate went red before it went green. A change that needed
  six attempts is worth a second look even when the final diff is small.
- **Abstained** — whether the agent stopped and asked rather than guessing. Stopping is
  the behaviour the anti-loop rules ask for, so it should be visible when it happens
  rather than only inferable when it does not.

## Guidance

- **Dead ends are the point.** A mistake that shows up in three session logs becomes a
  CI rule. If you hide the fumbling, the same fumble recurs forever.
- One line per field is enough — this is a signal feed, not an essay.
- Never leave a `<placeholder>` in place; the validator rejects them, because an unfilled
  field reads as a completed one to everyone except the person who wrote it.
