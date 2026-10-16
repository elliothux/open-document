import { record } from "./validation.js";

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
    reason: string;
    deleteReason: string;
  })[];
}
export type DocxPictureEdit =
  (DocxPicture & { action: "resize" }) | { action: "delete"; id: number };
export function checkDocxPictureEdit(value: unknown): void {
  const edit = record(value);
  if (edit.action === "resize") return checkDocxPicture(value);
  if (
    edit.action !== "delete" ||
    !Number.isSafeInteger(edit.id) ||
    Number(edit.id) < 0 ||
    Number(edit.id) > 2147483647
  )
    throw new Error("Invalid DOCX picture action");
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
      typeof image.reason !== "string" ||
      typeof image.deleteReason !== "string" ||
      !Number.isSafeInteger(image.id) ||
      Number(image.id) < 0
    )
      throw new Error("Invalid DOCX picture entry");
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
