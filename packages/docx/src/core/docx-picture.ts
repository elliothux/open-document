import { record, integer } from "@open-document/wasm/abi/validation";
import { checkDrawingAnchor, type DrawingAnchor } from "./preview.js";
import type { DocxPosition } from "./docx-hit.js";
import { isDocxSelection } from "./docx-search.js";
import { checkDocxHyperlink } from "./docx-format.js";
export type { DrawingAnchor, DrawingAxis } from "./preview.js";

export interface DocxPicture {
  id: number;
  width: number;
  height: number;
  /** Fractions removed from left, top, right and bottom of the source. */
  crop: [number, number, number, number];
}
export interface DocxDrawingPositionEdit {
  action: "position";
  id: number;
  anchor: DrawingAnchor | null;
  /** Move a floating drawing's logical anchor into an ordinary body paragraph. */
  target?: DocxPosition;
}
export interface DocxDrawingHyperlinkEdit {
  action: "hyperlink";
  id: number;
  target: string | null;
}
export interface DocxDrawingHyperlink {
  target: string | null;
  reason: string;
}
export interface DocxPictures {
  revision: number;
  images: (DocxPicture & {
    name: string;
    selected: boolean;
    reason: string;
    deleteReason: string;
    replaceReason: string;
    anchor: DrawingAnchor | null;
    positionReason: string;
    hyperlink: DocxDrawingHyperlink;
  })[];
}
export type DocxPictureEdit =
  | (DocxPicture & { action: "resize" })
  | { action: "insert"; width: number; height: number; bytes: Uint8Array }
  | { action: "replace"; id: number; bytes: Uint8Array }
  | { action: "delete"; id: number }
  | DocxDrawingHyperlinkEdit
  | DocxDrawingPositionEdit;

export type DocxDrawingGestureCommand =
  | { action: "begin"; drawing: number; handle: 0 | 1 | 2 | 3 | 4 }
  | { action: "cancel"; id: number }
  | {
      action: "update" | "commit";
      id: number;
      dx: number;
      dy: number;
      /** Reanchor a pointer move on this page; deltas use page-local points. */
      page?: number;
    };

export function checkDocxDrawingGesture(value: unknown): void {
  const change = record(value);
  if (
    change.action === "begin" &&
    integer(change.drawing, 0, 2147483647) &&
    integer(change.handle, 0, 4)
  )
    return;
  if (!integer(change.id, 1, 2147483647))
    throw new Error("Invalid drawing gesture identity");
  if (change.action === "cancel") return;
  if (
    (change.action === "update" || change.action === "commit") &&
    (change.page === undefined || integer(change.page, 0, 2147483647)) &&
    [change.dx, change.dy].every(
      (v) =>
        typeof v === "number" && Number.isFinite(v) && Math.abs(v) <= 14400,
    )
  )
    return;
  throw new Error("Invalid drawing gesture command");
}
export function checkDocxPictureEdit(value: unknown): void {
  const edit = record(value);
  if (edit.action === "hyperlink") return checkDocxDrawingHyperlinkEdit(edit);
  if (edit.action === "resize") return checkDocxPicture(value);
  if (edit.action === "position") return checkDocxDrawingPosition(edit);
  if (edit.action === "insert") {
    checkDocxPicture({
      id: 0,
      width: edit.width,
      height: edit.height,
      crop: [0, 0, 0, 0],
    });
    checkImageBytes(edit.bytes);
    return;
  }
  if (
    (edit.action !== "delete" && edit.action !== "replace") ||
    !Number.isSafeInteger(edit.id) ||
    Number(edit.id) < 0 ||
    Number(edit.id) > 2147483647
  )
    throw new Error("Invalid DOCX picture action");
  if (edit.action === "replace") checkImageBytes(edit.bytes);
}
export function checkDocxDrawingHyperlinkEdit(value: unknown): void {
  const edit = record(value);
  if (edit.action !== "hyperlink" || !integer(edit.id, 0, 2147483647))
    throw new Error("Invalid DOCX drawing hyperlink identity");
  checkDocxHyperlink(edit.target);
}
export function checkDocxDrawingPosition(value: unknown): void {
  const edit = record(value);
  if (edit.action !== "position" || !integer(edit.id, 0, 2147483647))
    throw new Error("Invalid DOCX drawing identity or action");
  checkDrawingAnchor(edit.anchor);
  if (
    edit.target !== undefined &&
    (edit.anchor === null ||
      !isDocxSelection({ anchor: edit.target, focus: edit.target }))
  )
    throw new Error("Invalid DOCX drawing anchor target");
}
function checkImageBytes(bytes: unknown): void {
  if (!(bytes instanceof Uint8Array) || !bytes.length)
    throw new Error("Invalid DOCX image input");
}
export function checkDocxPicture(value: unknown): void {
  const picture = record(value),
    crop: unknown = picture.crop;
  if (
    !Number.isSafeInteger(picture.id) ||
    Number(picture.id) < 0 ||
    ![picture.width, picture.height].every(
      (v) =>
        typeof v === "number" && Number.isFinite(v) && v >= 0.1 && v <= 14400,
    ) ||
    !Array.isArray(crop) ||
    crop.length !== 4 ||
    crop.some(
      (v: unknown) =>
        typeof v !== "number" || !Number.isFinite(v) || v < 0 || v >= 1,
    ) ||
    crop[0] + crop[2] >= 1 ||
    crop[1] + crop[3] >= 1
  )
    throw new Error("Invalid DOCX picture size or crop");
}
