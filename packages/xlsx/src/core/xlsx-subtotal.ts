import { integer, record } from "@open-document/wasm/abi/validation";
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
    (range.bottom - range.top + 1) * (range.right - range.left + 1) > 4096 ||
    !integer(settings.groupColumn, range.left, range.right) ||
    !integer(settings.valueColumn, range.left, range.right) ||
    settings.groupColumn === settings.valueColumn ||
    !subtotalFunctions.some((operation) => operation === settings.operation)
  )
    throw new Error("Invalid subtotal settings");
}
export function xlsxSubtotals(value: unknown): XlsxSubtotals {
  const result = record(value);
  checkXlsxSubtotalSettings({
    range: result.range,
    groupColumn: result.groupColumn,
    valueColumn: result.valueColumn,
    operation: result.operation,
  });
  const source = xlsxBounds(result.range),
    target = xlsxBounds(result.resultRange),
    width = target.right - target.left + 1,
    height = target.bottom - target.top + 1;
  if (
    !integer(result.revision, 0, 2147483647) ||
    typeof result.sheet !== "string" ||
    !result.sheet ||
    result.sheet.length > 65535 ||
    source.top !== target.top ||
    source.left !== target.left ||
    source.right !== target.right ||
    height * width > 4096 ||
    result.grandTotalRow !== target.bottom ||
    !Array.isArray(result.groups) ||
    !result.groups.length ||
    result.groups.length > 200 ||
    !Array.isArray(result.preview) ||
    result.preview.length !== Math.min(10, height)
  )
    throw new Error("Invalid subtotal preview");
  let next = source.top + 1;
  for (const value of result.groups) {
    const group = record(value);
    if (
      typeof group.label !== "string" ||
      !group.label.isWellFormed() ||
      group.label.length > 32767 ||
      group.firstRow !== next ||
      !integer(group.lastRow, next, target.bottom - 2) ||
      group.totalRow !== Number(group.lastRow) + 1
    )
      throw new Error("Invalid subtotal group");
    next = Number(group.totalRow) + 1;
  }
  if (
    next !== target.bottom ||
    height - result.groups.length - 2 < 1 ||
    height - result.groups.length - 2 > source.bottom - source.top
  )
    throw new Error("Invalid subtotal row mapping");
  let units = 0;
  for (const row of result.preview) {
    if (!Array.isArray(row) || row.length !== width)
      throw new Error("Invalid subtotal preview width");
    for (const text of row) {
      if (
        typeof text !== "string" ||
        !text.isWellFormed() ||
        text.length > 32767
      )
        throw new Error("Invalid subtotal preview text");
      units += text.length;
      if (units > 1048576)
        throw new Error("Subtotal preview exceeds text budget");
    }
  }
  return value as XlsxSubtotals;
}
