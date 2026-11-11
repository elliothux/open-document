import {
  xlsxDuplicateCells,
  xlsxWorksheetColumns,
} from "@open-document/wasm/engine-source";
import { integer, record } from "@open-document/wasm/abi/validation";

export interface XlsxDuplicateSettings {
  range: string;
  header: boolean;
  /** One-based worksheet columns used for equality. */
  columns: number[];
}
export interface XlsxDuplicates extends XlsxDuplicateSettings {
  /** Native table totals are excluded from comparisons and moved with the table. */
  totalRow: boolean;
  revision: number;
  sheet: string;
  keptRows: number[];
  removedRows: number[];
  resultRange: string;
  /** First ten retained data rows, using formatted values. */
  preview: string[][];
}
export function checkXlsxDuplicateSettings(value: unknown): void {
  const settings = record(value);
  if (
    Object.keys(settings).length !== 3 ||
    Object.keys(settings).some(
      (key) => !["range", "header", "columns"].includes(key),
    ) ||
    typeof settings.range !== "string" ||
    !settings.range ||
    settings.range.length > 64 ||
    typeof settings.header !== "boolean" ||
    !Array.isArray(settings.columns) ||
    !settings.columns.length ||
    settings.columns.length > xlsxDuplicateCells
  )
    throw new Error("Invalid duplicate settings");
  const seen = new Set<number>();
  for (const column of settings.columns) {
    if (!integer(column, 1, xlsxWorksheetColumns) || seen.has(Number(column)))
      throw new Error("Invalid duplicate comparison column");
    seen.add(Number(column));
  }
}
