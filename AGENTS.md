# AGENTS — Open Document

## Goal

- Replicate GenOffice's full document, spreadsheet, presentation, and PDF capabilities as an embeddable SDK. Use local `references/genoffice` for the feature inventory and UI interactions; use the App only for visual comparison acceptance and interaction reference. The target and boundaries belong in the [SDK contract](docs/references/sdk.md).
- This unreleased project has **zero users**. Deliver usable features first. Latest delivered phase is [P8 PDF operations](docs/implemented/p8-pdf-operations.md); follow the [roadmap](docs/references/roadmap.md) for phase status.
- Design from Day One for current requirements. Change the lowest affected layer directly. Update affected callers, tests, and docs; remove superseded implementations.
- Keep compatibility code only for document formats. Do not retain compatibility paths for old APIs, models, configuration, or development data.
- Build the smallest complete feature. Reuse existing code and add structure for a demonstrated gap. Feature priorities are P0 for core functionality, P1 for broader compatibility and performance, and P2 for secondary integrations such as AI, collaboration, and diff. These priorities are separate from roadmap phase IDs.
- Preserve document integrity, recovery, security, accessibility, and resource limits in every priority. During P0 feature work, address performance when a hang, unusable interaction, or resource failure blocks the feature.

## Execution

- Complete requested changes using the conversation and existing results. Reuse authorization already given. Ask only for missing decisions or new authority.
- Follow explicit user instructions over skill guidance. Read directory-specific instructions. If a skill would halt authorized work, link its file and quote the instruction.
- Prepare a reviewable result before seeking approval. External writes, commits, pushes, publication, deployment, destructive cleanup, and credential or permission changes require user authorization. Do not execute them without it.
- Work in this repository. Preserve unrelated edits, user data, reference checkouts, and compact failure evidence. Expand scope only with user authorization.
- When asked to commit/push, use current branches here and in `test-lab/`. Push the private commit before the parent gitlink. Branch changes and history rewriting need explicit authorization.
- Local bounded Docker work and reference clones under `references/` are authorized. Keep private inputs local and preserve unrelated resources.
- Handle routine work directly. Use subagents only for explicitly requested parallel work. After a context reset, resume the current goal.
- After two attempts without new evidence, reassess the blocker and choose another approach.

## Communication

These rules summarize dualface/ste-zh for user-facing replies.

- Answer first, then give necessary evidence and limitations. Describe results rather than each tool call.
- Use familiar words, concrete verbs, and active voice. Keep one fact or action per sentence. Put conditions before actions.
- Use one name per concept. Explain unfamiliar terms once. Preserve identifiers, commands, paths, and quoted output exactly.
- Separate completed work from verified behavior. Give the check method, result, and scope. Distinguish failure, unexecuted checks, and missing evidence.
- Label hypotheses and unknown facts. State how to resolve uncertainty.
- Use short paragraphs for ordinary answers. Use lists for parallel facts and numbered steps for procedures. Offer choices only for an actual user decision.
- Prefer positive instructions. For Chinese, aim for 30 characters per step and 40 per descriptive sentence.
- Converse in Chinese. Keep code, comments, API docs, commits, GitHub text, root `README.md`, and `AGENTS.md` in English. Preserve other documents' language.

## Implementation

- MoonBit owns document state, editing, layout, and serialization. TypeScript handles platform events, Worker communication, and rendering. Follow the [SDK contract](docs/references/sdk.md).
- Use strict TypeScript. Do not bypass errors with `any`, `@ts-ignore`, `@ts-nocheck`, double assertions, or relaxed compiler options.
- Keep first-party source files within 800 lines. Split by responsibility and export from the owning module.
- Use pinned toolchains and one lockfile per ecosystem. Regenerate generated files with their tools. Commands and module boundaries belong in [development](docs/references/development.md).
- Prefer ONLYOFFICE [core](https://github.com/ONLYOFFICE/core) and [sdkjs](https://github.com/ONLYOFFICE/sdkjs) for Office implementation, layout, algorithms, compatibility behavior, and independent test baselines. Use [LibreOffice](https://github.com/LibreOffice/core) second and [Collabora](https://github.com/CollaboraOnline/online.mirror) for supplementary browser cases. GenOffice defines feature and UI targets, not the Office engine implementation.
- Resolve implementation reference conflicts in that order within the format scope, honoring explicit user choices. Inspect upstream behavior and tests; preserve licenses and source attribution.

## Validation and resources

- Target **Chrome/Chromium only**, using the existing input method. Other browser engines, Windows/Word, and VoiceOver acceptance remain outside scope.
- Test user feature flows and observable results. Add checks for changed behavior or concrete integrity, security, recovery, and accessibility risks. Extend existing feature cases where possible.
- Review copy, labels, colors, styling, docs, and mechanical renames directly. Add no dedicated test or snapshot unless behavior, document fidelity, or accessibility changes.
- Use focused checks by default. Run the full suite only when focused checks cannot cover a named risk across the affected feature flows. Explain that risk first. Reuse applicable results and deliver once sufficient checks pass.
- Keep expectations independent. Never special-case fixtures in product code, weaken assertions, or hide failures to obtain a pass.
- Treat `test-lab/` as private resources governed by this file. Keep public builds independent of it. Execution details belong in [testing](docs/references/testing.md).
- Keep temporary output in `.temp/<purpose>/`, with one current run and one necessary baseline. Check combined root/private usage before expensive work; stop new runs at 2 GiB. Clean authorized task-owned output while preserving compact failure evidence. Keep standard build output in its normal location.

## Documentation

- Before writing docs, goals, plans, prompts, or `AGENTS.md`, read https://developers.openai.com/api/docs/guides/latest-model and apply its current best practices.
- Maintain docs in `docs/` under its [organization rules](docs/references/README.md). Edit the owning document and link to it elsewhere. Keep proposals to user results, scope, implementation, and sufficient checks.
- Keep root `README.md` to introduction, **WIP** status, documentation links, and license. Move completed plans only after updating indexes and inbound links.
- For docs-only changes, check `git diff --check`, affected links, commands, and status claims. Finish after these checks.

## Updating this file

Read this file in full and follow the guide above. Edit existing rules, merge duplicates, and remove conflicts. Use short, positive instructions. Keep implementation details in their owning docs. Review the diff and run `git diff --check`.
