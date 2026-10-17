import { record } from "./validation.js";

export interface XlsxName {
  name: string;
  /** Stable worksheet part identity, or null for workbook scope. */
  scope: string | null;
  formula: string;
  hidden: boolean;
  readOnlyReason: string;
}

export interface XlsxNames {
  entries: XlsxName[];
  readOnlyReason: string;
}

export type XlsxNameEdit =
  | {
      action: "name";
      /** null creates a name; otherwise edits or renames it within the same scope. */
      original: string | null;
      name: string;
      scope: string | null;
      formula: string;
    }
  | { action: "nameDelete" | "nameSelect"; name: string; scope: string | null };

function text(value: unknown, max: number): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= max &&
    value.isWellFormed()
  );
}

export function checkXlsxNameEdit(value: unknown): void {
  const change = record(value),
    set = change.action === "name";
  if (
    !["name", "nameDelete", "nameSelect"].includes(String(change.action)) ||
    !text(change.name, 255) ||
    (change.scope !== null && !text(change.scope, 65535)) ||
    (set &&
      ((change.original !== null && !text(change.original, 255)) ||
        !text(change.formula, 8192))) ||
    Object.keys(change).some(
      (key) =>
        !(
          set
            ? ["action", "original", "name", "scope", "formula"]
            : ["action", "name", "scope"]
        ).includes(key),
    )
  )
    throw new Error("Invalid defined name command");
}

export function xlsxNames(value: unknown): XlsxNames {
  const state = record(value);
  if (
    !Array.isArray(state.entries) ||
    state.entries.length > 4096 ||
    typeof state.readOnlyReason !== "string"
  )
    throw new Error("Invalid defined names state");
  let units = 0;
  const keys = new Set<string>();
  const entries = state.entries.map((value: unknown): XlsxName => {
    const item = record(value);
    if (
      !text(item.name, 255) ||
      (item.scope !== null && !text(item.scope, 65535)) ||
      typeof item.formula !== "string" ||
      !item.formula.isWellFormed() ||
      typeof item.hidden !== "boolean" ||
      typeof item.readOnlyReason !== "string"
    )
      throw new Error("Invalid defined name entry");
    units += item.name.length + item.formula.length + (item.scope?.length ?? 0);
    const key = JSON.stringify([item.scope, item.name.toUpperCase()]);
    if (units > 1048576 || keys.has(key))
      throw new Error("Invalid defined names budget or identity");
    keys.add(key);
    return {
      name: item.name,
      scope: item.scope,
      formula: item.formula,
      hidden: item.hidden,
      readOnlyReason: item.readOnlyReason,
    };
  });
  return { entries, readOnlyReason: state.readOnlyReason };
}
