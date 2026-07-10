# Session log

The last block of **every agent PR description** (athena spec 04 §2.6). It is the raw
material the monthly [session-log harvest](../cadences.md) turns into lint rules — so
write the dead ends down honestly; a clean-looking log with the struggle hidden starves
the flywheel.

Paste this at the bottom of the PR body and fill it:

```
## Session log
Tool/model: <tool>/<model> | Packet: #<issue>
Tried: <the approach that worked, in one line>
Dead ends: <what was attempted and abandoned, and why — this is the valuable part>
Decisions made and why: <choices not spelled out in the packet, with the reason>
```

## Guidance

- **Dead ends are the point.** A mistake that shows up in three session logs becomes a
  CI rule. If you hide the fumbling, the same fumble recurs forever.
- One line per field is enough — this is a signal feed, not an essay.
- "Decisions made and why" captures the judgment calls a reviewer would otherwise have to
  reverse-engineer from the diff.
