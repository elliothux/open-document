import { record, integer } from "./validation.js";
import { encodeBytes } from "./session.js";
import { checkDrawingAnchor, type DrawingAnchor } from "./preview.js";
import type { DocxPosition } from "./docx-hit.js";
import { isDocxSelection } from "./docx-search.js";
export type { DrawingAnchor, DrawingAxis } from "./preview.js";

export interface DocxPicture {
  id: number;
  width: number;
  height: number;
  /** Fractions removed from left, top, right and bottom of the source. */
  crop: [number, number, number, number];
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
  })[];
}
export type DocxPictureEdit =
  | (DocxPicture & { action: "resize" })
  | { action: "insert"; width: number; height: number; bytes: Uint8Array }
  | { action: "replace"; id: number; bytes: Uint8Array }
  | { action: "delete"; id: number }
  | {
      action: "position";
      id: number;
      anchor: DrawingAnchor | null;
      /** Move a floating picture's logical anchor into an ordinary body paragraph. */
      target?: DocxPosition;
    };

export type DocxPictureGestureCommand =
  | { action: "begin"; picture: number; handle: 0 | 1 | 2 | 3 | 4 }
  | { action: "cancel"; id: number }
  | {
      action: "update" | "commit";
      id: number;
      dx: number;
      dy: number;
      /** Reanchor a pointer move on this page; deltas use page-local points. */
      page?: number;
    };

export function checkDocxPictureGesture(value: unknown): void {
  const change = record(value);
  if (
    change.action === "begin" &&
    integer(change.picture, 0, 2147483647) &&
    integer(change.handle, 0, 4)
  )
    return;
  if (!integer(change.id, 1, 2147483647))
    throw new Error("Invalid picture gesture identity");
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
  throw new Error("Invalid picture gesture command");
}
export function checkDocxPictureEdit(value: unknown): void {
  const edit = record(value);
  if (edit.action === "resize") return checkDocxPicture(value);
  if (edit.action === "position") {
    if (!integer(edit.id, 0, 2147483647))
      throw new Error("Invalid DOCX picture identity");
    checkDrawingAnchor(edit.anchor);
    if (
      edit.target !== undefined &&
      (edit.anchor === null ||
        !isDocxSelection({ anchor: edit.target, focus: edit.target }))
    )
      throw new Error("Invalid DOCX picture anchor target");
    return;
  }
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
function checkImageBytes(bytes: unknown): void {
  if (!(bytes instanceof Uint8Array) || !bytes.length || bytes.length > 4194304)
    throw new Error("Invalid DOCX image input");
}
export function prepareDocxPictureEdit(picture: DocxPictureEdit): unknown {
  checkDocxPictureEdit(picture);
  return picture.action === "replace" || picture.action === "insert"
    ? { ...picture, bytes: encodeBytes(picture.bytes) }
    : picture;
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
export function docxPictures(value: unknown): DocxPictures {
  const result = record(value);
  if (
    !Number.isSafeInteger(result.revision) ||
    Number(result.revision) < 0 ||
    !Array.isArray(result.images) ||
    result.images.length > 256
  )
    throw new Error("Invalid DOCX picture list");
  for (const value of result.images) {
    const image = record(value);
    if (
      typeof image.name !== "string" ||
      typeof image.selected !== "boolean" ||
      typeof image.reason !== "string" ||
      typeof image.deleteReason !== "string" ||
      typeof image.replaceReason !== "string" ||
      typeof image.positionReason !== "string" ||
      !Number.isSafeInteger(image.id) ||
      Number(image.id) < 0
    )
      throw new Error("Invalid DOCX picture entry");
    checkDrawingAnchor(image.anchor);
    if (!image.reason) checkDocxPicture(image);
    else if (
      image.width !== 0 ||
      image.height !== 0 ||
      !Array.isArray(image.crop) ||
      image.crop.length !== 4 ||
      image.crop.some((v: unknown) => v !== 0)
    )
      throw new Error("Invalid protected DOCX picture");
  }
  return value as DocxPictures;
}
