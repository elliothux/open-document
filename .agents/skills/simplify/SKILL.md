---
name: simplify
description: Simplify recently changed Open Document implementation code while preserving requested behavior. Use to remove duplicate ownership, redundant conversions, forwarding layers, and superseded implementations in MoonBit and TypeScript.
---

# Simplify

Follow the root [AGENTS.md](../../../AGENTS.md) for scope, authorization, and validation. Review requests produce findings; change requests authorize local edits within the requested scope.

## Inspect the affected path

Start with the requested diff and trace its producers, consumers, and existing equivalents. Look for duplicated state, repeated conversions, pass-through modules, and workarounds near a symptom. Expand only far enough to fix the shared cause and remove superseded wiring.

## Preserve the project boundaries

- Keep document state, editing, layout, and serialization in MoonBit. Keep platform events, Worker communication, and rendering in TypeScript. See the [SDK contract](../../../docs/references/sdk.md).
- Derive host views from core results. Remove independently editable copies of the document model.
- Preserve necessary Worker and Wasm ABI boundaries. Simplify redundant forwarding within a layer without removing ordering, revision checks, cancellation, or disposal behavior.
- Convert data once at its owning boundary. Reuse source types and existing APIs where they fit.
- Replace symptom-level compensation with the shared rule. Preserve format compatibility, error reporting, resource limits, and document recovery.
- Update affected callers and remove replaced APIs and implementations together. Root rules govern compatibility and test selection.

## Finish

Review the diff for the requested behavior and orphaned callers. Use the smallest sufficient checks from the root rules and [testing guide](../../../docs/references/testing.md). Leave code unchanged when simplification would add complexity or lacks a demonstrated benefit.
