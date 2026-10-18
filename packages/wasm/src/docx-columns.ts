import { record } from "./validation.js";

export interface DocxColumns {
  count: number;
  gap: number;
  separator: boolean;
}

export function checkDocxColumns(value: unknown): void {
  if (value === null) return;
  const columns = record(value);
  if (
    Object.keys(columns).length !== 3 ||
    Object.keys(columns).some(
      (key) => !["count", "gap", "separator"].includes(key),
    ) ||
    typeof columns.count !== "number" ||
    !Number.isInteger(columns.count) ||
    columns.count < 1 ||
    columns.count > 12 ||
    typeof columns.gap !== "number" ||
    !Number.isFinite(columns.gap) ||
    columns.gap < 0 ||
    columns.gap > 14400 ||
    !Number.isInteger(columns.gap * 20) ||
    typeof columns.separator !== "boolean"
  )
    throw new Error("Invalid DOCX columns");
}
