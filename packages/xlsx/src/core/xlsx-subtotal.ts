import { integer, record } from "@open-document/wasm/abi/validation";
import { xlsxSubtotalCells } from "@open-document/wasm/engine-source";
import { xlsxBounds } from "./xlsx-geometry.js";

export const subtotalFunctions = ["sum", "count", "average"] as const;
export interface XlsxSubtotalSettings {
  range: string;
  groupColumn: number;
  valueColumn: number;
  operation: (typeof subtotalFunctions)[number];
}
export interface XlsxSubtotals extends XlsxSubtotalSettings {
  revision: number;
  sheet: string;
  resultRange: string;
  grandTotalRow: number;
  groups: {
    label: string;
    firstRow: number;
    lastRow: number;
    totalRow: number;
  }[];
  preview: string[][];
}
export function checkXlsxSubtotalSettings(value: unknown): void {
  const settings = record(value),
    range = xlsxBounds(settings.range);
  if (
    Object.keys(settings).length !== 4 ||
    Object.keys(settings).some(
      (key) =>
        !["range", "groupColumn", "valueColumn", "operation"].includes(key),
    ) ||
    range.bottom === range.top ||
    range.right === range.left ||
    (range.bottom - range.top + 1) * (range.right - range.left + 1) >
      xlsxSubtotalCells ||
    !integer(settings.groupColumn, range.left, range.right) ||
    !integer(settings.valueColumn, range.left, range.right) ||
    settings.groupColumn === settings.valueColumn ||
    !subtotalFunctions.some((operation) => operation === settings.operation)
  )
    throw new Error("Invalid subtotal settings");
}
