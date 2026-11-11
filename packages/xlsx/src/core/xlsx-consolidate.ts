import { record } from "@open-document/wasm/abi/validation";
import {
  xlsxConsolidationSourceCells,
  xlsxConsolidationSources,
} from "@open-document/wasm/engine-source";
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
    settings.sources.length > xlsxConsolidationSources ||
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
    if (cells > xlsxConsolidationSourceCells)
      throw new Error("Consolidation sources exceed limits");
  }
}
