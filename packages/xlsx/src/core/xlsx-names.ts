import { record } from "@open-document/wasm/abi/validation";
import {
  xlsxDefinedNameUnits,
  xlsxFormulaSourceUnits,
} from "@open-document/wasm/engine-source";

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
    !text(change.name, xlsxDefinedNameUnits) ||
    (change.scope !== null && !text(change.scope, 65535)) ||
    (set &&
      ((change.original !== null &&
        !text(change.original, xlsxDefinedNameUnits)) ||
        !text(change.formula, xlsxFormulaSourceUnits))) ||
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
