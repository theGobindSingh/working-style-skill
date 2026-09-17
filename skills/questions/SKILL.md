---
name: questions
description: Resolve open questions the way Gobind wants: research first, then one numbered batch with a recommendation and stakes per question, before any implementation. Use when starting non-trivial work with unknowns, when he says "ask me questions if needed", "do you have anything to ask", "questions?" or /gobind:questions, and always before switching to autonomous mode.
argument-hint: "[topic or task]"
---

Gobind answers questions once, up front, with evidence in hand. He does not answer them mid-task, and he dislikes questions a doc already answers. Topic: `$ARGUMENTS`.

1. Go read-only. Read `docs/status.md`, the repo's CLAUDE.md / AGENTS.md, and any doc that owns the domain (PRODUCT, DESIGN, CONVENTIONS). Spawn Explore agents in parallel for anything that needs a code sweep. Do not edit anything yet.
2. Strike every question the docs or code answer. Strike every engineering choice; those are yours to make (file layout, which helper to reuse, how to test, how to wire). Keep only content, product, process and stop-condition questions, and anything where two readings would produce materially different work.
3. Ask what is left in one message using `${CLAUDE_PLUGIN_ROOT}/assets/templates/questions.md.template`: numbered, most structural first, each with the option you would take and why, and its stakes in one line. Three to six questions is normal; more means you did not research enough.
4. End with: "If I hear nothing, I proceed with the recommendations above." If he is about to go autonomous, say that these are the last questions.
5. Write his answers into `docs/status.md` (or the plan doc) so they survive compaction, then start.

A terse reply ("no, sticky, not in the footer") is the answer. Adjust and move on; do not re-confirm.
