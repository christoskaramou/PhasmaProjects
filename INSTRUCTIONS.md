# Project instructions

This is the shared entry point for every model working in this workspace.

## Working rules

- Read applicable AGENTS.md, CLAUDE.md and other provider/project instructions. Preserve them. If rules conflict, identify the conflict rather than silently replacing rules.
- Inspect relevant live source before editing. Preserve unrelated changes. Run focused checks and report what was actually verified.
- Projects run on a PhasmaEngine checkout beside this repo (`../PhasmaEngine`); see `docs/wiki/index.md` before moving either checkout.

## Project knowledge

Use the active workspace wiki index supplied by Harness with each worker request (Settings > Wiki). Its location can change. This repo's own index is `docs/wiki/index.md`; do not start another one. Search focused pages with project_context when available, then verify claims in live source. Do not load the whole wiki.

## Improving these instructions

After a recurring correction, verified pitfall, or workflow change, propose a small update with supporting source references and a verification date. Keep this entry short; put detailed architecture and decisions in the wiki. Remove obsolete or duplicate guidance when proposing replacements. Apply updates only when the user authorizes them. Do not store secrets, raw conversations, or session diaries.
