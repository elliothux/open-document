import { integer } from "@open-document/wasm/abi/validation";
import { pptxSlideCountLimit } from "@open-document/wasm/engine-source";
import type { PptxFragmentMedia } from "./pptx-media.js";

export interface PptxImportInfo<Image = string, MediaBytes = string> {
  slides: { index: number; title: string; hidden: boolean }[];
  fonts: string[];
  /** Image sources for verification before committing. */
  images: Image[];
  media: PptxFragmentMedia<MediaBytes>[];
}

export type PptxImportCommand =
  | {
      operation: "inspectPptxSlides";
      revision: number;
      bytes: Uint8Array;
      indices: number[];
      prepareImages?: true;
      prepareResources?: true;
      verifyImages?: true;
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
    !Array.isArray(indices) ||
    indices.length > pptxSlideCountLimit ||
    (commit && !indices.length) ||
    indices.some(
      (index: unknown) => !integer(index, 0, pptxSlideCountLimit - 1),
    ) ||
    new Set(indices).size !== indices.length
  )
    throw new Error("Invalid PPTX import bytes or slide indices");
}
