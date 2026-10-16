import { record } from "./validation.js";

export interface DocxCellMargins {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export function checkDocxCellMargins(value: unknown): void {
  const margins = record(value);
  if (
    !["top", "right", "bottom", "left"].every((key) => {
      const number = margins[key];
      return (
        typeof number === "number" &&
        Number.isFinite(number) &&
        number >= 0 &&
        number <= 14400 &&
        Number.isInteger(number * 20)
      );
    })
  )
    throw new Error("Invalid cell margins");
}

export type DocxTableEdit =
  | {
      action:
        | "rowBefore"
        | "rowAfter"
        | "deleteRow"
        | "columnBefore"
        | "columnAfter"
        | "deleteColumn"
        | "unmerge"
        | "splitTable";
    }
  | { action: "merge"; rows: number; columns: number }
  | { action: "tableWidth" | "rowHeight"; value: number }
  | { action: "cellFill"; value: string | null }
  | { action: "cellVerticalAlign"; value: "top" | "center" | "bottom" | null }
  | { action: "cellMargins" | "tableMargins"; value: DocxCellMargins | null }
  | { action: "tableAlign"; value: "left" | "center" | "right" };

export function checkDocxTableEdit(value: unknown): void {
  const change = record(value);
  if (change.action === "tableAlign") {
    if (
      typeof change.value !== "string" ||
      !["left", "center", "right"].includes(change.value)
    )
      throw new Error("Invalid table alignment");
    return;
  }
  if (change.action === "cellMargins" || change.action === "tableMargins") {
    if (change.value !== null) checkDocxCellMargins(change.value);
    return;
  }
  if (change.action === "cellVerticalAlign") {
    if (
      change.value !== null &&
      (typeof change.value !== "string" ||
        !["top", "center", "bottom"].includes(change.value))
    )
      throw new Error("Invalid cell vertical alignment");
    return;
  }
  if (change.action === "cellFill") {
    if (
      change.value !== null &&
      (typeof change.value !== "string" || !/^[0-9a-f]{6}$/i.test(change.value))
    )
      throw new Error("Invalid cell fill");
    return;
  }
  if (change.action === "tableWidth" || change.action === "rowHeight") {
    if (
      typeof change.value !== "number" ||
      !Number.isFinite(change.value) ||
      change.value < 0 ||
      change.value > 14400 ||
      !Number.isInteger(change.value * 20) ||
      (change.action === "tableWidth" && change.value === 0)
    )
      throw new Error("Invalid table size");
    return;
  }
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
      "splitTable",
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
