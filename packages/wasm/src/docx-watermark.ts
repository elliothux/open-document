import { record, integer } from "./validation.js";
import { encodeBytes } from "./session.js";

export interface DocxTextWatermark {
  text: string;
  font: string;
  size: number;
  color: string;
  opacity: number;
  diagonal: boolean;
  bold: boolean;
  italic: boolean;
}
export interface DocxWatermarkState {
  revision: number;
  value: DocxWatermarkValue | null;
  mixed: boolean;
  reason: string;
  images: string[];
}

export interface DocxPictureWatermark {
  kind: "picture";
  image: string;
  width: number;
  height: number;
  opacity: number;
}
export type DocxWatermarkValue =
  { kind: "text"; value: DocxTextWatermark } | DocxPictureWatermark;
export type DocxWatermark =
  | { kind: "text"; value: DocxTextWatermark }
  | (Omit<DocxPictureWatermark, "image"> & { image: string | Uint8Array });

function imageKey(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.startsWith("watermark:") &&
    value.length > 10 &&
    value.length <= 4096 &&
    value.isWellFormed() &&
    Array.from(value).every((c) => {
      const n = c.codePointAt(0)!;
      return n >= 32 && ![127, 65534, 65535].includes(n);
    })
  );
}

export function checkDocxWatermark(
  value: unknown,
): asserts value is DocxWatermark | null {
  if (value === null) return;
  const mark = record(value);
  if (mark.kind === "text") {
    if (
      Object.keys(mark).length !== 2 ||
      Object.keys(mark).some((key) => !["kind", "value"].includes(key)) ||
      mark.value === null
    )
      throw new Error("Invalid text watermark value");
    checkDocxTextWatermark(mark.value);
    return;
  }
  if (
    mark.kind !== "picture" ||
    Object.keys(mark).length !== 5 ||
    Object.keys(mark).some(
      (key) => !["kind", "image", "width", "height", "opacity"].includes(key),
    ) ||
    !(
      imageKey(mark.image) ||
      (mark.image instanceof Uint8Array &&
        mark.image.length > 0 &&
        mark.image.length <= 4194304)
    ) ||
    ![mark.width, mark.height].every(
      (v) =>
        typeof v === "number" && Number.isFinite(v) && v >= 0.1 && v <= 14400,
    ) ||
    typeof mark.opacity !== "number" ||
    !Number.isFinite(mark.opacity) ||
    mark.opacity < 0 ||
    mark.opacity > 1
  )
    throw new Error("Invalid picture watermark");
}

export function encodeDocxWatermark(value: DocxWatermark | null): unknown {
  checkDocxWatermark(value);
  return value?.kind === "picture" && value.image instanceof Uint8Array
    ? { ...value, image: { bytes: encodeBytes(value.image) } }
    : value;
}

export function checkDocxTextWatermark(
  value: unknown,
): asserts value is DocxTextWatermark | null {
  if (value === null) return;
  const mark = record(value);
  const singleLine = (text: unknown): text is string =>
    typeof text === "string" &&
    !!text.trim() &&
    text.length <= 256 &&
    text.isWellFormed() &&
    Array.from(text).every((c) => {
      const n = c.codePointAt(0)!;
      return n >= 32 && ![127, 8232, 8233, 65534, 65535].includes(n);
    });
  if (
    Object.keys(mark).length !== 8 ||
    Object.keys(mark).some(
      (key) =>
        ![
          "text",
          "font",
          "size",
          "color",
          "opacity",
          "diagonal",
          "bold",
          "italic",
        ].includes(key),
    ) ||
    !singleLine(mark.text) ||
    !singleLine(mark.font) ||
    mark.font.includes("|") ||
    typeof mark.size !== "number" ||
    !Number.isInteger(mark.size * 2) ||
    mark.size < 0.5 ||
    mark.size > 1638 ||
    typeof mark.color !== "string" ||
    !/^[0-9a-fA-F]{6}$/.test(mark.color) ||
    typeof mark.opacity !== "number" ||
    !Number.isFinite(mark.opacity) ||
    mark.opacity < 0 ||
    mark.opacity > 1 ||
    typeof mark.diagonal !== "boolean" ||
    typeof mark.bold !== "boolean" ||
    typeof mark.italic !== "boolean"
  )
    throw new Error("Invalid text watermark");
}

export function docxWatermarkState(input: unknown): DocxWatermarkState {
  const state = record(input);
  if (
    typeof state.revision !== "number" ||
    !integer(state.revision, 0, 0x7fffffff) ||
    typeof state.mixed !== "boolean" ||
    typeof state.reason !== "string" ||
    state.reason.length > 8192 ||
    (!!state.reason && (state.value !== null || state.mixed)) ||
    Object.keys(state).length !== 5 ||
    !Array.isArray(state.images) ||
    state.images.length > 3 ||
    !state.images.every(imageKey) ||
    new Set(state.images).size !== state.images.length ||
    (!!state.reason && state.images.length !== 0)
  )
    throw new Error("Invalid text watermark state");
  checkDocxWatermark(state.value);
  let value: DocxWatermarkValue | null;
  if (state.value?.kind === "picture") {
    const image = state.value.image;
    if (typeof image !== "string" || !state.images.includes(image))
      throw new Error("Invalid watermark image state");
    value = { ...state.value, image };
  } else value = state.value;
  return {
    revision: state.revision,
    value,
    mixed: state.mixed,
    reason: state.reason,
    images: state.images,
  };
}
