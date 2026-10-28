import { integer, record } from "@open-document/wasm/abi/validation";
import { xlsxBounds } from "./xlsx-geometry.js";

export const consolidateFunctions = [
  "sum",
  "count",
  "average",
  "max",
  "min",
] as const;
export interface XlsxConsolidateSettings {
  sources: { sheet: string; range: string }[];
  target: string;
  operation: (typeof consolidateFunctions)[number];
  leftLabels: boolean;
}
export interface XlsxConsolidation extends XlsxConsolidateSettings {
  revision: number;
  sheet: string;
  resultRange: string;
  overwrittenCells: number;
  preview: string[][];
}
export function checkXlsxConsolidateSettings(value: unknown): void {
  const settings = record(value);
  if (
    Object.keys(settings).length !== 4 ||
    Object.keys(settings).some(
      (key) => !["sources", "target", "operation", "leftLabels"].includes(key),
    ) ||
    !Array.isArray(settings.sources) ||
    !settings.sources.length ||
    settings.sources.length > 32 ||
    !consolidateFunctions.some((fn) => fn === settings.operation) ||
    typeof settings.leftLabels !== "boolean"
  )
    throw new Error("Invalid consolidation settings");
  const target = xlsxBounds(settings.target);
  if (target.top !== target.bottom || target.left !== target.right)
    throw new Error("Select one consolidation destination cell");
  let cells = 0;
  for (const entry of settings.sources) {
    const source = record(entry),
      range = xlsxBounds(source.range);
    if (
      Object.keys(source).length !== 2 ||
      Object.keys(source).some((key) => key !== "sheet" && key !== "range") ||
      typeof source.sheet !== "string" ||
      !source.sheet ||
      source.sheet.length > 65535 ||
      !source.sheet.isWellFormed() ||
      (settings.leftLabels && range.left === range.right)
    )
      throw new Error("Invalid consolidation source");
    cells += (range.bottom - range.top + 1) * (range.right - range.left + 1);
    if (cells > 65536) throw new Error("Consolidation sources exceed limits");
  }
}
export function xlsxConsolidation(value: unknown): XlsxConsolidation {
  const result = record(value);
  checkXlsxConsolidateSettings({
    sources: result.sources,
    target: result.target,
    operation: result.operation,
    leftLabels: result.leftLabels,
  });
  const target = xlsxBounds(result.target),
    range = xlsxBounds(result.resultRange),
    rows = range.bottom - range.top + 1,
    columns = range.right - range.left + 1;
  if (
    !integer(result.revision, 0, 2147483647) ||
    typeof result.sheet !== "string" ||
    !result.sheet ||
    result.sheet.length > 65535 ||
    range.top !== target.top ||
    range.left !== target.left ||
    rows * columns > 4096 ||
    !integer(result.overwrittenCells, 0, rows * columns) ||
    !Array.isArray(result.preview) ||
    result.preview.length !== Math.min(rows, 10)
  )
    throw new Error("Invalid consolidation preview");
  let units = 0;
  for (const row of result.preview) {
    if (!Array.isArray(row) || row.length !== columns)
      throw new Error("Invalid consolidation preview width");
    for (const text of row) {
      if (
        typeof text !== "string" ||
        !text.isWellFormed() ||
        text.length > 32767
      )
        throw new Error("Invalid consolidation preview text");
      units += text.length;
      if (units > 1048576)
        throw new Error("Consolidation preview exceeds text budget");
    }
  }
  return value as XlsxConsolidation;
}
