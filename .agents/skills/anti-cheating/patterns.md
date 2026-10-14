# Open Document audit patterns

Use these patterns to evaluate candidates from [SKILL.md](SKILL.md). Establish the controlling data flow before reporting a finding.

## Production surfaces

- `modules/core`, `modules/layout`, and `modules/formats`: document parsing, editing, layout, and serialization.
- `modules/bridge` and `packages/wasm`: core/host ABI and validation.
- `packages/web`: Worker transport, input ordering, and rendering.
- `test-lab/tests`, `test-lab/tools`, and `test-lab/cases`: private cases, oracles, execution selection, and reporting.

Read guidance or prompts when the changed workflow uses them; check whether they encode one sample's answer as a general rule.

## Candidates worth tracing

| Candidate | Evidence needed |
| --- | --- |
| Product branch checks a fixture filename, test ID, sample hash, or expected text | The value selects product behavior rather than test setup or legitimate input semantics |
| Layout constant matches one reference screenshot | The constant lacks a format, font, geometry, or documented reference rule and changes results for that sample |
| Golden output comes from the SDK being tested | The output is presented as an independent compatibility expectation without external verification |
| Assertion or threshold changes with a failing implementation | The new expectation lacks independent evidence of a changed contract |
| Runner omits a case, catches an error, or substitutes an empty result | The report still grants success for required behavior that did not execute or failed |

## Legitimate input-driven rules

Format namespaces, content types, ZIP part names, relationship types, font metrics, script properties, and field codes can require exact literals. Trace them to the declared format or reference behavior.

UI labels, ordinary document text, generated output, and fixture literals in private test setup are not evidence of cheating by themselves. Snapshots can verify a regression without proving compatibility; judge them by the claim they support. Equivalent spellings or aliases required by a document format remain valid compatibility work.

## Search without expanding the audit

Use `git diff` and `git ls-files --others --exclude-standard` in each repository to establish changed surfaces. Search distinctive literals with `rg -n -F -- 'literal' <affected-paths>`. Start with the changed files and related cases; expand to consumers only when the candidate needs it. Missing private cases or reference evidence limit the conclusion rather than proving misconduct.
