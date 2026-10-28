import { record, hasFields, arrayOf, glyphs } from "./validation.js";
export interface ShapeBatch {
  text: string;
  carets: { offset: number; before: number; after: number }[];
  glyphs: {
    id: number;
    cluster: number;
    font: number;
    outline: string;
    x: number;
    y: number;
    scale: number;
    advance: number;
    yAdvance: number;
    xOffset: number;
    yOffset: number;
  }[];
  outlines: { key: string; path: string }[];
  runs: {
    start: number;
    end: number;
    level: number;
    font: number;
    script: string;
    language: string;
  }[];
  fonts: {
    identity: string;
    sha256: string;
    face: number;
    variation: string;
    upem: number;
    ascent: number;
    descent: number;
    bbox: number[];
    capHeight: number;
    italicAngle: number;
  }[];
  diagnostics: { code: string; cluster: number; codepoint: number }[];
  width: number;
  fontBytes: number;
  outlineBytes: number;
}

export interface TextStyle {
  font: string;
  size: number;
  color: string;
  underline: boolean;
  strike: boolean;
  highlight: string;
  script: "baseline" | "superscript" | "subscript";
  spacing: number;
}

export function shapeBatch(value: unknown): ShapeBatch {
  const object = record(value);
  if (
    !hasFields(value, ["text"], ["width", "fontBytes", "outlineBytes"]) ||
    !glyphs(object.glyphs) ||
    !arrayOf(
      object.carets,
      (entry) =>
        hasFields(entry, [], ["offset", "before", "after"]) &&
        Number.isSafeInteger(record(entry).offset) &&
        Number(record(entry).offset) >= 0,
    ) ||
    !arrayOf(object.outlines, (entry) =>
      hasFields(entry, ["key", "path"], []),
    ) ||
    !arrayOf(object.runs, (entry) =>
      hasFields(
        entry,
        ["script", "language"],
        ["start", "end", "level", "font"],
      ),
    ) ||
    !arrayOf(
      object.fonts,
      (entry) =>
        hasFields(
          entry,
          ["identity", "variation", "sha256"],
          ["face", "upem", "ascent", "descent", "capHeight", "italicAngle"],
        ) &&
        arrayOf(
          record(entry).bbox,
          (value) => typeof value === "number" && Number.isFinite(value),
        ),
    ) ||
    !arrayOf(object.diagnostics, (entry) =>
      hasFields(entry, ["code"], ["cluster", "codepoint"]),
    )
  )
    throw new Error("Invalid shape batch returned by Wasm");
  return value as ShapeBatch;
}

export type NavigationDirection =
  "left" | "right" | "up" | "down" | "home" | "end";
