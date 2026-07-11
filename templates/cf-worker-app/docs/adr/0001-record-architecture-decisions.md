# 1. Record architecture decisions

Status: Accepted

## Context

We need to record the architectural decisions made on this project, so that six months
from now "why does this exist" has an answer.

## Decision

We will use Architecture Decision Records, as described by Michael Nygard, kept in
`docs/adr/`. Each ADR follows the format Status / Context / Decision / Consequences /
Revisit-trigger (mirroring the Artemis DECISIONS.md format).

## Consequences

Every non-obvious architectural choice gets a short, append-only record. New ADRs are
numbered sequentially. Superseded ADRs are marked, not deleted.

## Revisit trigger

Never — this is the meta-decision that establishes the practice.
