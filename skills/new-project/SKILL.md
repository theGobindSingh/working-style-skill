---
name: new-project
description: Scaffold a new project the way Gobind likes (CLAUDE.md, docs index, status/log docs, conventions, pnpm) from the plugin templates. Use when he says /gobind:new-project, "set up a new project", "starting a new repo", "set up the CLAUDE.md the way i like", or "scaffold".
argument-hint: "<path> [one-line description]"
---

Target: `$ARGUMENTS`. Templates live in `${CLAUDE_PLUGIN_ROOT}/assets/templates/`.

1. Resolve the path (relative paths are under `~/Programming/` or `~/programming/` : search). If the folder exists and is non-empty, list what is there and merge rather than overwrite; never clobber an existing CLAUDE.md or docs without saying so.
2. Create from templates, filling every `<PLACEHOLDER>` you can from the description and leaving the rest as visible placeholders:
   - `CLAUDE.md` from `CLAUDE.md.template`
   - `docs/status.md`, `docs/log.md`, `docs/PRODUCT.md`, `docs/DESIGN.md`, `docs/CONVENTIONS.md`
   - `.claude/settings.json` with `{"env": {"CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "5"}}` only (hooks come from this plugin, do not duplicate them)
   - `.gitignore` entries: `.claude/gobind/`, `.claude/settings.local.json`, `.playwright-mcp/`, `.scratch/`, `.env*` (keep `!.env.example`)
   - `.playwright-mcp/.gitkeep`
3. If it is a node/web project: `pnpm` only. Ask before running `pnpm create` / installing a framework, because that is a product decision; otherwise stop after the docs.
4. Do not run `git init`, do not commit. Git is his.
5. Reply in three lines: what was created, what placeholders remain, and the one next decision he needs to make.
