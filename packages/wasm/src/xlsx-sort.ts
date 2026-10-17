import { record, integer } from "./validation.js";

export interface XlsxSortKey {
  /** One-based worksheet column for rows, or row for columns. */
  index: number;
  descending: boolean;
}
export interface XlsxSortSettings {
  rows: boolean;
  header: boolean;
  caseSensitive: boolean;
  keys: XlsxSortKey[];
}
export function checkXlsxSort(value: unknown): void {
  const change = record(value);
  if (
    typeof change.range !== "string" ||
    !change.range ||
    change.range.length > 64 ||
    typeof change.rows !== "boolean" ||
    typeof change.header !== "boolean" ||
    typeof change.caseSensitive !== "boolean" ||
    !Array.isArray(change.keys) ||
    change.keys.length < 1 ||
    change.keys.length > 16
  )
    throw new Error("Invalid sort settings");
  const seen = new Set<number>();
  for (const value of change.keys) {
    const key = record(value);
    if (
      !integer(key.index, 1, change.rows ? 16384 : 1048576) ||
      typeof key.descending !== "boolean" ||
      seen.has(Number(key.index))
    )
      throw new Error("Invalid sort key");
    seen.add(Number(key.index));
  }
}
