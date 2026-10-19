import { record } from "./validation.js";

export const pptxPlaceholderTypes = [
  "title",
  "body",
  "ctrTitle",
  "subTitle",
  "dt",
  "ftr",
  "sldNum",
  "hdr",
  "obj",
  "chart",
  "tbl",
  "clipArt",
  "dgm",
  "media",
  "sldImg",
  "pic",
] as const;
export type PptxPlaceholderType = (typeof pptxPlaceholderTypes)[number];
export interface PptxPlaceholder {
  type: PptxPlaceholderType;
  index: number;
}

export function pptxPlaceholder(value: unknown): PptxPlaceholder | null {
  if (value === null) return null;
  const result = record(value);
  if (
    typeof result.type !== "string" ||
    !pptxPlaceholderTypes.some((type) => type === result.type) ||
    typeof result.index !== "number" ||
    !Number.isInteger(result.index) ||
    result.index < 0 ||
    result.index > 4294967295 ||
    Object.keys(result).length !== 2
  )
    throw new Error("Invalid placeholder definition");
  return value as PptxPlaceholder;
}

export function checkPptxPlaceholderQuery(value: unknown): void {
  const result = record(value);
  if (typeof result.reason !== "string" || result.reason.length > 8192)
    throw new Error("Invalid placeholder protection reason");
  pptxPlaceholder(result.value);
}
