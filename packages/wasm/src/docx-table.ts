import { record } from "./validation.js";

export type DocxTableEdit =
  | {
      action:
        | "rowBefore"
        | "rowAfter"
        | "deleteRow"
        | "columnBefore"
        | "columnAfter"
        | "deleteColumn"
        | "unmerge";
    }
  | { action: "merge"; rows: number; columns: number };

export function checkDocxTableEdit(value: unknown): void {
  const change = record(value);
  if (
    change.action === "merge" &&
    typeof change.rows === "number" &&
    typeof change.columns === "number"
  ) {
    checkDocxTableSize(change.rows, change.columns);
    return;
  }
  if (
    typeof change.action !== "string" ||
    ![
      "rowBefore",
      "rowAfter",
      "deleteRow",
      "columnBefore",
      "columnAfter",
      "deleteColumn",
      "unmerge",
    ].includes(change.action)
  )
    throw new Error("Invalid table edit");
}

/** Bounds match the core's table creation limit. */
export function checkDocxTableSize(rows: number, columns: number): void {
  if (
    !Number.isInteger(rows) ||
    !Number.isInteger(columns) ||
    rows < 1 ||
    rows > 1000 ||
    columns < 1 ||
    columns > 63 ||
    rows * columns > 4096
  )
    throw new Error("Invalid table dimensions");
}
