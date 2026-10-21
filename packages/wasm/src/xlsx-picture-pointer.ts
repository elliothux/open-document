import { record, integer } from "./validation.js";
import { xlsxRect } from "./xlsx-geometry.js";
import { xlsxViewport, type XlsxViewport, type XlsxQuery } from "./xlsx.js";
import { xlsxQuery } from "./xlsx-query.js";
import type { DrawRect } from "./drawing.js";

export interface XlsxPictureRegion {
  rect: DrawRect;
  clip: DrawRect;
}
export interface XlsxPictureSelection {
  revision: number;
  sheet: string;
  id: string | null;
  regions: XlsxPictureRegion[];
}
export interface XlsxPictureGesture {
  handle: number;
  dx: number;
  dy: number;
  commit: boolean;
}
export interface XlsxPicturePreview {
  query: XlsxQuery | null;
  drawing: XlsxViewport | null;
  selection: XlsxPictureSelection;
}
export function pictureRegions(
  value: unknown,
): asserts value is XlsxPictureRegion[] {
  if (!Array.isArray(value) || value.length > 4)
    throw new Error("Invalid worksheet picture regions");
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
      throw new Error("Invalid worksheet picture clip");
  }
}
export function xlsxPictureSelection(value: unknown): XlsxPictureSelection {
  const state = record(value);
  if (
    !integer(state.revision, 0, 2147483647) ||
    typeof state.sheet !== "string" ||
    !(
      state.id === null ||
      (typeof state.id === "string" && /^[1-9][0-9]*$/.test(state.id))
    )
  )
    throw new Error("Invalid worksheet picture selection");
  pictureRegions(state.regions);
  if (state.id === null && state.regions.length)
    throw new Error("Unselected worksheet picture has regions");
  return value as XlsxPictureSelection;
}
export function checkPictureGesture(value: XlsxPictureGesture): void {
  if (
    !integer(value.handle, 0, 4) ||
    ![value.dx, value.dy].every(
      (n) => Number.isFinite(n) && Math.abs(n) <= 14400,
    ) ||
    typeof value.commit !== "boolean"
  )
    throw new Error("Invalid worksheet picture pointer delta");
}
export function xlsxPicturePreview(value: unknown): XlsxPicturePreview {
  const result = record(value);
  xlsxPictureSelection(result.selection);
  if (result.query !== null) xlsxQuery(result.query);
  if (result.drawing !== null) xlsxViewport(result.drawing);
  if ((result.query === null) === (result.drawing === null))
    throw new Error("Invalid worksheet picture preview state");
  return value as XlsxPicturePreview;
}
