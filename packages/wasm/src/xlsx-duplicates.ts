import { xlsxBounds as bounds } from "./xlsx-geometry.js";
import { integer, record } from "./validation.js";

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
    settings.columns.length > 4096
  )
    throw new Error("Invalid duplicate settings");
  const seen = new Set<number>();
  for (const column of settings.columns) {
    if (!integer(column, 1, 16384) || seen.has(Number(column)))
      throw new Error("Invalid duplicate comparison column");
    seen.add(Number(column));
  }
}
export function xlsxDuplicates(value: unknown): XlsxDuplicates {
  const result = record(value),
    source = bounds(result.range),
    target = bounds(result.resultRange);
  checkXlsxDuplicateSettings({
    range: result.range,
    header: result.header,
    columns: result.columns,
  });
  if (
    !integer(result.revision, 0, 2147483647) ||
    typeof result.sheet !== "string" ||
    typeof result.totalRow !== "boolean" ||
    !result.sheet ||
    result.sheet.length > 65535 ||
    !Array.isArray(result.columns) ||
    result.columns.some(
      (c) => Number(c) < source.left || Number(c) > source.right,
    ) ||
    !Array.isArray(result.keptRows) ||
    !Array.isArray(result.removedRows) ||
    result.keptRows.length + result.removedRows.length !==
      source.bottom -
        source.top +
        1 -
        Number(result.header) -
        Number(result.totalRow)
  )
    throw new Error("Invalid duplicate preview");
  const seen = new Set<number>(),
    first = source.top + Number(result.header),
    last = source.bottom - Number(result.totalRow);
  if (
    (result.totalRow && first > last) ||
    (first <= last && result.keptRows[0] !== first)
  )
    throw new Error("Duplicate removal must retain the first data row");
  for (const rows of [result.keptRows, result.removedRows]) {
    let previous = first - 1;
    for (const row of rows) {
      if (
        !integer(row, first, last) ||
        Number(row) <= previous ||
        seen.has(Number(row))
      )
        throw new Error("Invalid duplicate row mapping");
      previous = Number(row);
      seen.add(previous);
    }
  }
  if (
    target.top !== source.top ||
    target.left !== source.left ||
    target.right !== source.right ||
    target.bottom !==
      Math.max(
        source.top,
        first + result.keptRows.length + Number(result.totalRow) - 1,
      ) ||
    !Array.isArray(result.preview) ||
    result.preview.length !== Math.min(10, result.keptRows.length)
  )
    throw new Error("Invalid duplicate result range");
  let units = 0;
  for (const row of result.preview) {
    if (!Array.isArray(row) || row.length !== source.right - source.left + 1)
      throw new Error("Invalid duplicate preview width");
    for (const text of row) {
      if (
        typeof text !== "string" ||
        !text.isWellFormed() ||
        text.length > 32767
      )
        throw new Error("Invalid duplicate preview text");
      units += text.length;
      if (units > 1048576)
        throw new Error("Duplicate preview exceeds text budget");
    }
  }
  return value as XlsxDuplicates;
}
