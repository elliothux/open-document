import { record } from "@open-document/wasm/abi/validation";

export interface DocxColumns {
  count: number;
  gap: number;
  separator: boolean;
  custom: { width: number; gap: number }[];
}

export function checkDocxColumns(value: unknown): void {
  if (value === null) return;
  const columns = record(value);
  if (
    Object.keys(columns).length !== 4 ||
    Object.keys(columns).some(
      (key) => !["count", "gap", "separator", "custom"].includes(key),
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
    typeof columns.separator !== "boolean" ||
    !Array.isArray(columns.custom) ||
    (columns.custom.length !== 0 && columns.custom.length !== columns.count)
  )
    throw new Error("Invalid DOCX columns");
  for (const item of columns.custom) {
    const column = record(item);
    if (
      Object.keys(column).length !== 2 ||
      Object.keys(column).some((key) => !["width", "gap"].includes(key)) ||
      typeof column.width !== "number" ||
      !Number.isFinite(column.width) ||
      column.width < 12 ||
      column.width > 14400 ||
      !Number.isInteger(column.width * 20) ||
      typeof column.gap !== "number" ||
      !Number.isFinite(column.gap) ||
      column.gap < 0 ||
      column.gap > 14400 ||
      !Number.isInteger(column.gap * 20)
    )
      throw new Error("Invalid DOCX custom column");
  }
}
