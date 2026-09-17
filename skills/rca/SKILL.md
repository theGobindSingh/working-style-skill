---
name: rca
description: Root-cause-first bug workflow for a bug or a client's bug list. Use when Gobind pastes bugs, says "some bugs", "james sent bugs", "fix these", "RCA", or /gobind:rca, and whenever a fix would otherwise be attempted from a theory instead of evidence.
argument-hint: "<bug list or pointer>"
---

Bugs: `$ARGUMENTS`

Gobind's rule: "rather than fixing, spend more time on finding RCA and right analysis." Client theories have all been wrong before. Symptoms usually share a cause.

1. **List the bugs** as numbered items with the exact symptom, the reporter's theory (marked as a theory), and how to reproduce. If reproduction steps are missing, that is the first task.
2. **RCA phases, read-only, one per medium or large bug**, in parallel where they do not share state. For each: reproduce, trace the real flow from the code (not from the theory), grep the callers, and prove the cause with evidence (file:line, command output, a failing check). Explicitly test the reporter's theory and record whether it is confirmed or disproven.
3. **Shared-cause pass**: before any fix, compare the proven causes. Group bugs that route through one cause; fix that once where all the callers meet.
4. **Fix phases only from proven causes**, following the delegation tree in the working-style skill for anything bigger than one sitting. Each fix gets its own verification (the repro now passes, plus lint/typecheck/build/tests).
5. **Escalation caps**: three failed fix attempts on one bug means stop and question the architecture or the diagnosis, not a fourth attempt. Say so.
6. **Recap**: per bug: cause (with evidence), fix, verification (VERIFIED / NOT VERIFIED / BLOCKED), and which theories were disproven. Bad news first. Record the causes in docs/log.md.
