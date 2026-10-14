---
name: anti-cheating
description: Audit Open Document changes for fixture-specific production branches, circular expectations, and hidden test failures. Use for a requested anti-cheating review of implementation code, test oracles, runners, or guidance; ordinary code review does not require this audit.
---

# Anti-Cheating Audit

Use the root [AGENTS.md](../../../AGENTS.md) for execution policy. Report findings; apply fixes only when requested. Product behavior follows document inputs and format contracts. Test expectations need an independent basis.

## Review scope

Honor the requested file, diff, or commit range. With no range specified, inspect staged, unstaged, and untracked changes in the parent repository and available private `test-lab/` checkout. Include unpushed commits relative to each repository's configured upstream merge base. State the bases used; if one is unavailable, review the available scope and report the history limitation. Read related callers only as needed to resolve a candidate.

Private tests and fixtures live in `test-lab/`. Inspect its own Git diff as well as the parent's gitlink. If the private checkout is unavailable, identify the missing test evidence and continue the production review.

## Find and evaluate candidates

1. Trace changed production branches to their input fields and format rules. Cross-search distinctive sample names, hashes, expected strings, and numeric values from related tests.
2. Inspect changed expectations, snapshots, thresholds, case selection, and pass/fail reporting. Establish whether each change follows an independent contract or reference result.
3. Classify matches with [patterns.md](patterns.md). A literal match alone is not a finding.

For each candidate, ask:

- Would this behavior still belong if the fixture or test were removed?
- Does it generalize to other documents with the same format properties?
- Does the expectation come from a contract or independent reference, rather than copying the result under test?
- Could the runner report success while skipping the intended case or hiding its failure?

Use ONLYOFFICE core/sdkjs first and LibreOffice second when establishing reference behavior, honoring explicit user decisions. Reuse existing evidence; an audit does not require compiling reference repositories or running a full suite.

## Report

Lead with findings and reviewed scope. For each finding, give `path:line`, the production or reporting effect, the matching case or contract, and the smallest shared fix. Distinguish proven coupling from an unresolved suspicion. If none remain, say no findings were identified in the reviewed scope and name missing evidence.

When fixes are requested, implement the input-driven format rule or restore independent expectations and visible failures. Keep fixture-specific setup and fault injection in private tests.
