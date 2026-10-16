export type DocxTableEdit =
  | "rowBefore"
  | "rowAfter"
  | "deleteRow"
  | "columnBefore"
  | "columnAfter"
  | "deleteColumn";

export function checkDocxTableEdit(change: DocxTableEdit): void {
  if (
    ![
      "rowBefore",
      "rowAfter",
      "deleteRow",
      "columnBefore",
      "columnAfter",
      "deleteColumn",
    ].includes(change)
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
