import {
  xlsxWorksheetColumns,
  xlsxWorksheetRows,
} from "@open-document/wasm/engine-source";
import type { DrawRect } from "@open-document/wasm/abi/drawing";

export function xlsxBounds(
  value: unknown,
  maxCells = 4096,
): {
  top: number;
  bottom: number;
  left: number;
  right: number;
} {
  if (typeof value !== "string") throw new Error("Invalid XLSX range");
  const match =
    /^([A-Z]{1,3})([1-9]\d{0,6})(?::([A-Z]{1,3})([1-9]\d{0,6}))?$/u.exec(value);
  if (!match || match[0] !== value) throw new Error("Invalid XLSX range");
  const column = (text: string) =>
    Array.from(text).reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0);
  const result = {
    top: Number(match[2]),
    bottom: Number(match[4] ?? match[2]),
    left: column(match[1]!),
    right: column(match[3] ?? match[1]!),
  };
  if (
    result.top > result.bottom ||
    result.bottom > xlsxWorksheetRows ||
    result.left > result.right ||
    result.right > xlsxWorksheetColumns ||
    (result.bottom - result.top + 1) * (result.right - result.left + 1) >
      maxCells
  )
    throw new Error("XLSX range exceeds bounds");
  return result;
}

export interface XlsxSelectionGeometry extends DrawRect {
  rects: DrawRect[];
}
