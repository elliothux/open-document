# AGENTS — Open Document

## Working agreement

- This file governs first-party work in this repository. Read any more specific `AGENTS.md` before editing its directory. Reference-repository instructions apply only within those repositories and do not authorize publishing, pushing, or changing external resources.
- Inspect relevant source, tests, documentation, and runtime evidence before answering, diagnosing, reviewing, or planning. Those requests do not automatically authorize implementation. Change requests authorize in-scope local edits and the smallest sufficient validation.
- External writes, deployment, publishing, destructive actions, permission or credential changes, and material scope expansion require explicit user authorization. Do not automatically commit, push, create pull requests, or clean the workspace.
- When the user requests a commit or push, use the current branch in this repository and `test-lab/`. Do not create or switch branches unless the user explicitly requests it. Push the private submodule commit before pushing the parent gitlink; do not force-push or rewrite history.
- The user authorizes direct use of local Docker for development and testing, including pulling or building test images and running bounded containers, without further confirmation. Keep private inputs and evidence local; preserve unrelated Docker resources. This does not authorize remote Docker services, publishing images, deployment, or credential changes.
- Preserve uncommitted changes, reference checkouts, and failure evidence. Cleanup and Day 1 design do not authorize deleting user data, resetting repositories, or rewriting Git history.
- Keep changes within this repository. Adjacent `lynx-os`, `open-compute`, and upstream repositories are references, not automatically part of the edit scope.
- Converse in Chinese. Lead with the result, followed by evidence, limitations, and necessary next steps. Write code identifiers, comments, API documentation, commit messages, and GitHub-facing text in English.
- Challenge incorrect premises, logical gaps, and overlooked costs. Verify rather than merely agree.

## Product and Day 1 design

- [SDK contract](docs/references/sdk.md) owns current product goals, technology choices, and core/host responsibilities. [P1](docs/implemented/p1-sdk-foundation.md), [P2](docs/implemented/p2-format-foundation.md), and [P3](docs/implemented/p3-docx-preview.md) record completed foundation and limited preview work. Research conclusions do not automatically become approved designs or dependencies.
- Build one final implementation path for current requirements. Do not prebuild compatibility layers, dual writes, backfills, or alternate engines for this project's unpublished old models, APIs, or development data.
- Day 1 does not waive compatibility obligations for user documents, declared file formats, or published public contracts. Explain changes to support scope; never silently corrupt or discard content or disguise failure as success.
- Keep one authority per concern. Fix root causes, update affected producers, consumers, tests, and documentation together, and remove implementations superseded by the change.
- Before adding an abstraction, cache, protocol, state machine, dependency, or plugin mechanism, identify its current user and the concrete capability gap. Prefer the standard library, platform facilities, and validated dependencies over frameworks for hypothetical scale or extension points.
- For complex changes, define a lightweight contract: goals, non-goals, constraints, side effects, completion evidence, and stop conditions. Simplification must preserve security, document integrity, error handling, and accessibility.
- Every new or materially revised P-numbered proposal, including subphases, must define its tests, fixtures, compatibility expectations, performance/resource checks, and acceptance evidence before implementation, following the [P-proposal verification contract](docs/references/README.md#p-编号方案的验证合同). Map each promised capability to concrete verification; explain non-applicable items and unresolved prerequisites. A generic promise to add tests or a link to the shared pipeline is not sufficient.

## Source, dependencies, and reference projects

- Follow P1's responsibility boundary between the MoonBit core and TypeScript hosts. Do not maintain independently editable document models on both sides.
- Use strict TypeScript for first-party functional JavaScript-family source. Do not bypass type problems with `any`, `@ts-ignore`, `@ts-nocheck`, double assertions, or relaxed compiler options.
- Organize modules by actual responsibility. All first-party test code, fixtures, expected results, reports, and executable loop tooling are private in the pinned `test-lab/` submodule. Product plans, research, and testing documentation belong only in the parent `docs/`. Public builds must not require the private checkout. Authorized maintainers read its `AGENTS.md` before test work. Explicitly requested placeholder packages expose no fake capabilities.
- Keep first-party source files within 800 lines. Split by responsibility rather than mechanically. Do not add barrel files that only aggregate or forward exports.
- Use the project's actual pinned toolchain, dependency manifests, and single lockfile for each dependency ecosystem. Do not hand-edit generated output or lockfiles. Do not describe unselected package managers or commands as established facts.
- Use `bun run check`, `bun run build`, and `bun run api` from the root. Maintainers run `bun run test` from the root to invoke the private `test-lab` loop; a missing checkout or any test failure must fail the command. Pin Bun in `packageManager` / `.bun-version` and MoonBit in `moon-toolchain`. Development setup and module boundaries live in `docs/references/development.md`.
- Use [LibreOffice](https://github.com/LibreOffice/core) and ONLYOFFICE ([core](https://github.com/ONLYOFFICE/core), [sdkjs](https://github.com/ONLYOFFICE/sdkjs)) as the primary references for document compatibility and implementation logic. Inspect the relevant upstream behavior and tests before adapting an implementation; upstream behavior is not automatically the Microsoft Office compatibility oracle.
- Root `references/` contains independent upstream research checkouts, including the primary reference repositories. It is ignored, may be absent in other checkouts, is distinct from `docs/references/`, and is not a build dependency. Cite upstream GitHub file links in maintained documentation instead of local `references/` paths. Preserve independent Git state; check source, dependency, font, and fixture licenses before porting, and retain required provenance notices.
- The user authorizes cloning additional reference repositories into root `references/` when needed for research, without further confirmation. Reuse existing checkouts where suitable; this authorization does not include overwriting or resetting them, adding product dependencies, or committing or pushing upstream changes.
- Prefer existing upstream implementations. Document the concrete gap when maintaining a patch; remove superseded local implementations when upstream covers it rather than retaining parallel paths.

## Testing and evidence

- Prefer LibreOffice and [Collabora Online](https://github.com/CollaboraOnline/online.mirror) as references for test cases and test design: use LibreOffice for document-model, layout, import/export, and round-trip assertions, and Collabora for browser interaction tests. Adapt relevant cases to the SDK's declared scope, verify fixture licenses and provenance, and keep all adapted test assets in private `test-lab/`.
- Choose the smallest sufficient checks for the risk. Cover key success and failure paths for behavior changes; add recovery checks when lifecycle or persistence changes require them.
- Preserve the first real failure cause and rerun after fixing it. Different browsers, configurations, or inputs are distinct checks; do not omit required coverage to reduce run counts. Keep testing policy in `docs/references/testing.md` and executable case selection in the private repository.
- Validate real-browser behavior, WasmGC execution, and file round trips separately. Native results, mocks, CI configuration, and upstream READMEs do not replace evidence from the target environment.
- Never special-case fixture names, test IDs, sample hashes, or expected results in product code. General format rules must follow actual inputs and format contracts. Fault injection and fake data belong only in tests.
- Do not obtain a pass by weakening assertions, ignoring failures, lowering thresholds, or moving product logic outside the checked scope. Report missing tools or resources as limitations, not passes.
- Report a check as passing only after it exits successfully and executes the intended cases. Zero cases do not verify behavior. Record versions, inputs, and runtime environment; historical PASS results are not current acceptance.
- For documentation and policy changes, run at least `git diff --check` and verify local links, numbering, status, commands, and evidence claims. Documentation-only changes do not require compiling reference repositories.
- Keep raw logs, temporary run directories, caches, and retained failure evidence under `.temp/<purpose>/`. Leave standard build output in its tool-defined location. Do not delete failure evidence as cleanup or commit credentials, caches, or generated artifacts.

## Documentation

- [docs/references/README.md](docs/references/README.md) is the sole authority for documentation location, numbering, lifecycle, content, and evidence rules. Start navigation from [docs/README.md](docs/README.md).
- Write the root `AGENTS.md` and `README.md` in English. Preserve the language of other documents unless a translation is requested. While the SDK remains work in progress, prominently state **WIP** and the actual availability status in the root README.
- Keep the root README limited to the product introduction, current status, documentation links, and license. Put technology choices, architecture, interfaces, commands, validation, and detailed reference material in `docs/`.
- Update all inbound links and indexes when adding or moving documents. Do not retain old copies, redirects, or stubs. Do not move unimplemented capabilities into the completed directory.
