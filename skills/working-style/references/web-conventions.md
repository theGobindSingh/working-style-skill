# Web code conventions and copy rules

Defaults for Gobind's Next.js / TypeScript / Tailwind projects. A repo's own
`docs/CONVENTIONS.md` or `docs/DESIGN.md` wins where it exists; these fill the gaps and are
the baseline for a brand-new project.

## Styling

- **Tokens only.** Colours, type scale, spacing, radii come from the token system
  (`globals.css` / the design doc). No inline hex or HSL, no raw `px` font sizes, no magic
  numbers, no `dark:` colour literals (rely on ramp inversion so light and dark both work).
- **Tailwind utilities before the `style` prop.** Reach for `style` only for values Tailwind
  genuinely cannot express: runtime-computed values, `calc()`/`clamp()` from state, third-party
  integrations needing raw CSS. A `style` prop at a call site is a signal that a component
  variant, prop or token is missing. Add it there instead of patching the call site.
- Do not add new colour tokens or font variables without being asked.
- Reuse the design kit (signature techniques, component catalogue) rather than inventing
  parallel ornament.

## Files and structure

- **Kebab-case** for every file and folder. PascalCase stays for component identifiers and
  types in code; that is language, not filenames.
- **Folder + `index.tsx`** per unit, with optional `types.ts`, `styles.ts`, `constants.ts`.
  `index.tsx` is composition; static data lives in `constants.ts`, typed against `types.ts`.
- **~150 lines per file.** Past that, split by responsibility. Applies to every file, not just
  components.
- **`@` path aliases** over relative imports; relative only for true siblings.
- **Placement:** global, reusable UI (nav, footer, theme toggle, section header) in
  `src/components/`; page-specific sections (hero, about, work) in `src/features/` or
  `src/modules/`. Ask "will another page use this?" before choosing.
- Const arrow functions over `function` declarations. Mapper functions defined outside render
  unless a closure is needed.
- **pnpm only.** Never npm or yarn.

## Rendering, SEO, accessibility

- **Server components by default.** Add `"use client"` only at the smallest leaf that needs it.
- Everything indexable is SSR/SSG with per-page metadata, OG images, JSON-LD, sitemap, robots
  and canonicals. Core Web Vitals are a feature, not a nice-to-have; check bundle size after
  adding a dependency or route.
- Semantic HTML, visible focus, AA contrast, keyboard reachable.
- Every animation no-ops under `prefers-reduced-motion`.
- Use `next/image`, not raw `<img>`. Use the project's button and typography primitives, not
  raw elements, where the project defines them.

## Design bar

- "Simple, bland and basic" is a bug report. He wants micro-interactions, a clear design
  language, and polish. When a reference image or URL is given, match it closely: read the
  actual HTML and CSS, do not approximate from a screenshot.
- Verify in a real browser at mobile, tablet and desktop, light and dark, reduced motion.

## Lint and types

- ESLint green and auto-fixed; TypeScript strict; no `any`. Fix warnings too ("dont ignore,
  rather fix"). Never disable a rule to silence it without an agreed reason.
- Respect existing formatter hooks (a PostToolUse Prettier hook means do not also run
  `lint:fix` by hand).
- Never edit `.env*` files; ask.

## Copy rules

- **Never fabricate facts** about Gobind, a client, or a client's family. Use only supplied or
  verified details; otherwise leave an obvious placeholder like `<CLIENT_NAME>` and flag it.
- Client content (names, dialogue, emotional beats) belongs to the client. Draft freely, then
  surface for approval instead of baking unreviewed wording into a deliverable.
- His own bios and portfolio copy: first person ("I built", "I reduced"), plain and direct,
  outcomes before technology, no hype words. Do not pin him to specific frameworks; the point
  is that he is well versed across the web, not stuck with one stack.
- Use only verified metrics where a repo lists them. A specific-sounding fake number is worse
  than an honest `[metric TBD]` because it survives editing passes.
- Genericize prior-employer material in anything public or portfolio-facing; do not
  reintroduce real company or product names unless the repo's docs list them as allowed.
- Never read, edit or print `.env*` files or raw secret and cookie values.
- Run an AI-prose cleanup pass (the `stop-slop` skill where installed) on any text a human
  will read.
