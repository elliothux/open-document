import { record, integer } from "./validation.js";
import { xlsxRect } from "./xlsx-geometry.js";
import { xlsxViewport, type XlsxViewport } from "./xlsx-grid.js";
import type { XlsxQuery } from "./xlsx-query.js";
import { xlsxQuery } from "./xlsx-query.js";
import type { DrawRect } from "./drawing.js";

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
export function xlsxAnalysisPreview(value: unknown): XlsxAnalysisPreview {
  const result = record(value);
  if (
    Object.keys(result).length !== 2 ||
    (result.query === null) === (result.drawing === null)
  )
    throw new Error("Invalid analysis preview state");
  if (result.query !== null) xlsxQuery(result.query);
  if (result.drawing !== null) xlsxViewport(result.drawing);
  return value as XlsxAnalysisPreview;
}
export function drawingRegions(
  value: unknown,
): asserts value is XlsxDrawingRegion[] {
  if (!Array.isArray(value) || value.length > 4)
    throw new Error("Invalid worksheet object regions");
  for (const item of value) {
    const region = record(item),
      rect = xlsxRect(region.rect),
      clip = xlsxRect(region.clip);
    if (
      clip.x < 0 ||
      clip.y < 0 ||
      clip.width <= 0 ||
      clip.height <= 0 ||
      clip.x < rect.x - 0.000001 ||
      clip.y < rect.y - 0.000001 ||
      clip.x + clip.width > rect.x + rect.width + 0.000001 ||
      clip.y + clip.height > rect.y + rect.height + 0.000001
    )
      throw new Error("Invalid worksheet object clip");
  }
}
export function xlsxDrawingSelection(value: unknown): XlsxDrawingSelection {
  const state = record(value);
  if (
    !integer(state.revision, 0, 2147483647) ||
    typeof state.sheet !== "string" ||
    !(
      state.id === null ||
      (typeof state.id === "string" && /^[1-9][0-9]*$/.test(state.id))
    )
  )
    throw new Error("Invalid worksheet object selection");
  drawingRegions(state.regions);
  if (state.id === null && state.regions.length)
    throw new Error("Unselected worksheet object has regions");
  return value as XlsxDrawingSelection;
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
export function xlsxDrawingPreview(value: unknown): XlsxDrawingPreview {
  const result = record(value);
  xlsxDrawingSelection(result.selection);
  if (result.query !== null) xlsxQuery(result.query);
  if (result.drawing !== null) xlsxViewport(result.drawing);
  if ((result.query === null) === (result.drawing === null))
    throw new Error("Invalid worksheet object preview state");
  return value as XlsxDrawingPreview;
}
