# AGENTS — Open Document

## Priority

- This unreleased project has **zero users**. Deliver usable features first. [P4 DOCX editing](docs/p4-docx-editing.md) is the current work; [SDK goals](docs/references/sdk.md) own the product and core/host boundary.
- Change unpublished APIs, models, and development data directly through one implementation path. Preserve imported documents and declared file-format behavior. Migration and release machinery remain outside current scope.
- Start with one concrete user operation and finish the smallest complete implementation. Reuse existing code and add structure only for a demonstrated functional gap. Remove superseded paths.
- Prioritize functionality, document integrity, recovery, security, accessibility, and resource limits. Schedule performance work when a hang, unusable interaction, or resource failure blocks the feature.

## Execution and authorization

- Treat requests to build or fix something as authorization for in-scope local work and sufficient validation. Carry the result through implementation and delivery. Treat inspection and review requests within their requested scope.
- Use the conversation to resolve routine choices and reuse authorization already given. Ask only when missing information materially changes the result or an action needs new authority; continue independent authorized work meanwhile.
- Follow explicit user instructions over skill guidelines. Read directory-specific `AGENTS.md` before editing. If a skill would halt or redirect authorized work, link its file and quote the instruction, then apply the user's stated scope.
- Prepare a concrete, reviewable result before requesting any necessary final approval. External writes, commits, pushes, pull requests, deployment, publication, destructive cleanup, credential/system permission changes, and scope expansion require user authorization. Do not execute these without it.
- Work in this repository and preserve unrelated edits, user data, reference checkouts, and compact failure evidence. When asked to commit/push, use current branches here and in `test-lab/`, pushing the private commit before its parent gitlink. Branch changes and history rewriting require explicit authorization.
- Local bounded Docker development/testing and additional reference clones under `references/` are authorized. Keep private inputs local and preserve unrelated resources.
- Handle routine work directly; use subagents for explicitly requested parallel work. After a context reset, resume the current goal from existing results and outstanding work.
- Converse in Chinese. Write identifiers, comments, API documentation, commits, and GitHub text in English.

## Communication

The following self-contained rules summarize the writing principles of dualface/ste-zh. Apply them to user-facing replies, including progress updates. Keep code and generated files under the project's existing language rules.

- Lead with the useful information: answer, result and scope, current action, confirmed cause, or decision needed. Put supporting detail afterward.
- Give each concept one name and explain unfamiliar terms on first use. Preserve identifiers, commands, paths, error messages, and quoted output exactly.
- Use familiar words and direct verbs: write "changed the setting", not "performed an adjustment". Name who acts and what changes. Prefer positive instructions.
- Keep one action or fact per sentence. Put conditions before actions. For Chinese, aim for steps within 30 characters and descriptions within 40; split longer sentences naturally. Keep each paragraph to one topic.
- Separate work status from verification status. Use precise labels: completed, partial, not started, in progress, verified, unverified, failed, skipped, blocked, or unknown. State the scope. A finished edit does not establish that its behavior works.
- Support behavior and check results with the method, outcome, and coverage. Distinguish checks not run from missing evidence; preserve known failures. Reading source or documentation establishes what it says, not that runtime behavior passed.
- State uncertainty explicitly and give a way to resolve it. Label hypotheses and use only facts supported by user input, files, or tool output.
- Cite evidence where it helps assessment: file and line, full command and result, or source. Consolidate repeated evidence and report the result instead of narrating each tool call.
- Use short paragraphs for ordinary answers, lists for parallel facts, and numbered steps for procedures. Include only sections with content. Present numbered choices and consequences when a real user decision is needed, with the recommendation first.
- Before sending, check that the reply answers the question, uses consistent terms, separates completion from verification, and preserves the evidence. Keep the explanation natural and proportional to the request.

## Implementation

- MoonBit owns document state, editing, layout, and serialization. TypeScript hosts platform events, Worker communication, and rendering of derived output. Follow [development](docs/references/development.md) and [format contracts](docs/references/formats.md).
- Use strict TypeScript and fix types at their source. Do not bypass errors with `any`, `@ts-ignore`, `@ts-nocheck`, double assertions, or relaxed compiler options. Keep first-party source files within 800 lines, split by responsibility, and export from the owning module.
- Use pinned toolchains, manifests, and one lockfile per ecosystem. Regenerate generated output and lockfiles with their tools. Root commands are `bun run check`, `bun run build`, `bun run api`, and, when justified, `bun run test`.
- Prefer ONLYOFFICE ([core](https://github.com/ONLYOFFICE/core), [sdkjs](https://github.com/ONLYOFFICE/sdkjs)) for implementation, compatibility behavior, test design, and baselines; use [LibreOffice](https://github.com/LibreOffice/core) second and [Collabora](https://github.com/CollaboraOnline/online.mirror) for supplementary browser cases. Resolve reference conflicts in that order within the format scope, honoring explicit user choices.
- Inspect the feature's upstream behavior and tests, reuse suitable implementations, and retain licenses/provenance. Independent `references/` checkouts are optional research inputs; maintained docs cite upstream file links.

## Validation and resources

- Target **Chrome/Chromium only**, with the existing system input method. Keep Windows/Word, VoiceOver, and other browser-engine acceptance outside current scope.
- Select checks for the behavior changed. Documentation/comments/behavior-neutral metadata need diff and consistency checks. Local behavior needs nearby success/failure checks; persistence and lifecycle changes also need preservation/recovery checks.
- Use a full run for a functional milestone or a concrete cross-module risk, stating the reason first. Reuse applicable passing results. Once sufficient checks pass, deliver; expand or repeat only for a new change, failure, or unresolved concern.
- Treat `test-lab/` as this project's private test resource directory, governed by this root `AGENTS.md`. Keep tests, fixtures, independent expectations, reports, and tooling there; keep public builds independent of it. Maintain product/testing documents in `docs/`; [Testing](docs/references/testing.md) owns execution details.
- Register provenance/license, input hash, operation, independent expectation, and support scope in case manifests. Preserve actual reference identities and update them with the corresponding feature. This visible local resource directory is not a blind holdout.
- Use `.mbtx` for test process automation and Bun/Playwright for TypeScript tests. `test-lab/cases/suites.json` owns full-loop selection and package inventory; `test-lab/.agents/skills/document-test-loop/SKILL.md` provides loop/corpus execution details within the user's scope.
- Implement general format rules and keep assertions independent of product output. Never special-case fixtures in product code or weaken checks to obtain a pass. Report actual executed scope and distinguish pass, failure, skipped, and unverified; browser and independent file checks need their own evidence.
- Keep temporary output under `.temp/<purpose>/`, with one current run and one necessary baseline. Check combined root/private usage before expensive work; stop new runs at 2 GiB. Preserve compact reproductions and clean authorized task-owned output. Keep standard build output in its normal location.
- After two attempts without new evidence, reassess the functional blocker and choose a different approach. Report the usable operation, its entry point/output, and the exact remaining gap.

## Documentation

- Before writing or updating documentation, goals, plans, prompts, or `AGENTS.md`, read https://developers.openai.com/api/docs/guides/latest-model and apply its current best practices. Use the original page as the source. Express desired actions and results positively; retain explicit prohibitions for safety, authorization, and document integrity.
- Maintain plans and documentation in parent `docs/`, following its [organization rules](docs/references/README.md). Edit the existing authority and link to it from other documents.
- Keep a proposal to its user result, scope, implementation, and sufficient checks. Keep future work in its own phase and detailed run records in the private repository.
- Root `README.md` and `AGENTS.md` are English; preserve other documents' language. Keep the root README to introduction, **WIP**/actual availability, documentation links, and license.
- Keep unfinished work active. Update indexes and inbound links when moving completed docs. For documentation changes, check `git diff --check`, affected links, commands, and status; finish after those checks.
