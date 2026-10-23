import { record, integer } from "./validation.js";

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
export interface DocxTextWatermarkState {
  revision: number;
  value: DocxTextWatermark | null;
  mixed: boolean;
  reason: string;
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

export function docxTextWatermarkState(value: unknown): DocxTextWatermarkState {
  const state = record(value);
  if (
    typeof state.revision !== "number" ||
    !integer(state.revision, 0, 0x7fffffff) ||
    typeof state.mixed !== "boolean" ||
    typeof state.reason !== "string" ||
    state.reason.length > 8192 ||
    (!!state.reason && (state.value !== null || state.mixed)) ||
    Object.keys(state).length !== 4
  )
    throw new Error("Invalid text watermark state");
  checkDocxTextWatermark(state.value);
  return {
    revision: state.revision,
    value: state.value,
    mixed: state.mixed,
    reason: state.reason,
  };
}
