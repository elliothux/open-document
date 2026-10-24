import { integer, record } from "./validation.js";
import {
  checkPptxFragmentMedia,
  type PptxFragmentMedia,
} from "./pptx-media.js";

export interface PptxImportInfo {
  slides: { index: number; title: string; hidden: boolean }[];
  fonts: string[];
  /** Base64-encoded images for platform decoding before committing. */
  images: string[];
  media: PptxFragmentMedia[];
}

export type PptxImportCommand =
  | {
      operation: "inspectPptxSlides";
      revision: number;
      bytes: Uint8Array;
      indices: number[];
    }
  | {
      operation: "importPptxSlides";
      revision: number;
      bytes: Uint8Array;
      indices: number[];
      after: string;
      profile: Record<string, string>;
    };

export function checkPptxImportInput(
  bytes: unknown,
  indices: unknown,
  commit: boolean,
): void {
  if (
    !(bytes instanceof Uint8Array) ||
    !bytes.length ||
    bytes.length > 33554432 ||
    !Array.isArray(indices) ||
    indices.length > 256 ||
    (commit && !indices.length) ||
    indices.some((index: unknown) => !integer(index, 0, 255)) ||
    new Set(indices).size !== indices.length
  )
    throw new Error("Invalid PPTX import bytes or slide indices");
}

export function checkPptxImportInfo(
  value: unknown,
): asserts value is PptxImportInfo {
  const info = record(value);
  if (
    Object.keys(info).length !== 4 ||
    !Array.isArray(info.slides) ||
    !info.slides.length ||
    info.slides.length > 256 ||
    !Array.isArray(info.fonts) ||
    info.fonts.length > 256 ||
    info.fonts.some(
      (font: unknown) =>
        typeof font !== "string" ||
        !font ||
        !font.isWellFormed() ||
        font.length > 256,
    ) ||
    !Array.isArray(info.images) ||
    info.images.length > 256
  )
    throw new Error("Invalid PPTX import information");
  for (const [index, item] of info.slides.entries()) {
    const slide = record(item);
    if (
      Object.keys(slide).length !== 3 ||
      slide.index !== index ||
      typeof slide.hidden !== "boolean" ||
      typeof slide.title !== "string" ||
      !slide.title.isWellFormed() ||
      slide.title.length > 1048576
    )
      throw new Error("Invalid PPTX import slide catalog");
  }
  let units = 0;
  for (const image of info.images) {
    if (
      typeof image !== "string" ||
      !image.length ||
      image.length > 2796204 ||
      image.length % 4 !== 0 ||
      !/^[A-Za-z0-9+/]*={0,2}$/.test(image)
    )
      throw new Error("Invalid PPTX import image");
    units += image.length;
  }
  if (units > 5592408) throw new Error("PPTX import images exceed budget");
  checkPptxFragmentMedia(info.media);
}
