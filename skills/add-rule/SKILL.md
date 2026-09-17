---
name: add-rule
description: Record a new standing rule from Gobind in the right places so it sticks: the repo's CLAUDE.md, the plugin's references, and memory. Use when he says "add to claude.md", "remember this", "from now on", "write in notes", "make this a rule", or /gobind:add-rule.
argument-hint: "<the rule in his words>"
---

Rule as given: `$ARGUMENTS`

He iterates until the form is exact (example: "always start with 0", "so basically 3 numbers", "yes"), and then expects it written once and followed forever.

1. **Pin the exact form.** If any part is ambiguous (numbers, naming, scope), ask one short question now with an example of what you understood. Do not write until confirmed. If it is unambiguous, do not ask.
2. **Write it in three places**, each in one or two sentences with the why:
   - the repo's `CLAUDE.md` (or `AGENTS.md`) under the section it belongs to, with the date from `date -Iseconds`;
   - `${CLAUDE_PLUGIN_ROOT}/skills/working-style/references/working-agreement.md` if it applies beyond this repo (ask yourself: would he want this in every project?);
   - memory: one file with `type: feedback`, `**Why:**` quoting his words, `**How to apply:**`, plus its line in `MEMORY.md`.
3. If the rule is a hard prohibition an agent might break under pressure (git, secrets, servers, deletions), say so and propose a hook in `hooks/hooks.json` rather than only prose. Do not add the hook without his go.
4. Reply with the three locations and the exact sentence written.
