import { record, integer } from "@open-document/wasm/abi/validation";
import type { XlsxViewport } from "./xlsx-grid.js";
import type { XlsxQuery } from "./xlsx-query.js";
import type { DrawRect } from "@open-document/wasm/abi/drawing";

export interface XlsxDrawingRegion {
  rect: DrawRect;
  clip: DrawRect;
}
export interface XlsxDrawingSelection {
  revision: number;
  sheet: string;
  id: string | null;
  regions: XlsxDrawingRegion[];
}
export interface XlsxDrawingGesture {
  handle: number;
  dx: number;
  dy: number;
  commit: boolean;
  viewport?: {
    originX: number;
    originY: number;
    scrollX: number;
    scrollY: number;
  };
}
export interface XlsxDrawingPreview {
  query: XlsxQuery | null;
  drawing: XlsxViewport | null;
  selection: XlsxDrawingSelection;
}
export interface XlsxAnalysisPreview {
  query: XlsxQuery | null;
  drawing: XlsxViewport | null;
}
export function checkDrawingGesture(value: XlsxDrawingGesture): void {
  if (
    !integer(value.handle, 0, 4) ||
    ![value.dx, value.dy].every(
      (n) => Number.isFinite(n) && Math.abs(n) <= 14400,
    ) ||
    typeof value.commit !== "boolean"
  )
    throw new Error("Invalid worksheet object pointer delta");
  if (value.viewport !== undefined) {
    const view = record(value.viewport);
    if (
      Object.keys(view).length !== 4 ||
      ![view.originX, view.originY].every(
        (n) =>
          typeof n === "number" && Number.isFinite(n) && n >= 0 && n <= 14400,
      ) ||
      ![view.scrollX, view.scrollY].every(
        (n) =>
          typeof n === "number" && Number.isFinite(n) && n >= 0 && n <= 1e9,
      )
    )
      throw new Error("Invalid worksheet object pointer viewport");
  }
}
