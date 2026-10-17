import { record } from "./validation.js";

const slots = [
  "dk1",
  "lt1",
  "dk2",
  "lt2",
  "accent1",
  "accent2",
  "accent3",
  "accent4",
  "accent5",
  "accent6",
  "hlink",
  "folHlink",
] as const;
export type DocxThemeSlot = (typeof slots)[number];
export interface DocxThemeColors {
  revision: number;
  colors: { slot: DocxThemeSlot; color: string | null; reason: string }[];
}
export interface DocxThemeFontPair {
  major: string;
  minor: string;
}
export interface DocxThemeFonts {
  revision: number;
  fonts: { kind: "major" | "minor"; font: string | null; reason: string }[];
}
function fontFamily(value: unknown): value is string {
  return (
    typeof value === "string" &&
    !!value.trim() &&
    value.length <= 200 &&
    value.isWellFormed() &&
    !value.startsWith("+") &&
    !value.includes("|") &&
    !value.includes("\n") &&
    !value.includes("\r") &&
    [...value].every((c) => c === "\t" || c.codePointAt(0)! >= 32) &&
    !value.includes("\ufffe") &&
    !value.includes("\uffff")
  );
}
export function checkDocxThemeFonts(value: unknown): void {
  const pair = record(value);
  if (
    Object.keys(pair).length !== 2 ||
    !fontFamily(pair.major) ||
    !fontFamily(pair.minor)
  )
    throw new Error("Invalid DOCX theme font pair");
}
export function docxThemeFonts(value: unknown): DocxThemeFonts {
  const query = record(value);
  if (
    typeof query.revision !== "number" ||
    !Number.isSafeInteger(query.revision) ||
    query.revision < 0 ||
    !Array.isArray(query.fonts) ||
    query.fonts.length !== 2
  )
    throw new Error("Invalid DOCX theme fonts");
  const seen = new Set<unknown>();
  for (const value of query.fonts) {
    const font = record(value);
    if (
      typeof font.kind !== "string" ||
      !["major", "minor"].includes(font.kind) ||
      seen.has(font.kind) ||
      typeof font.reason !== "string" ||
      (font.font === null
        ? !font.reason
        : font.font !== "" && !fontFamily(font.font))
    )
      throw new Error("Invalid DOCX theme font");
    seen.add(font.kind);
  }
  return value as DocxThemeFonts;
}
export function checkDocxThemeColor(slot: unknown, color: unknown): void {
  if (
    !slots.some((value) => value === slot) ||
    typeof color !== "string" ||
    !/^[0-9a-f]{6}$/i.test(color)
  )
    throw new Error("Invalid DOCX theme color");
}
export function docxThemeColors(value: unknown): DocxThemeColors {
  const query = record(value);
  if (
    typeof query.revision !== "number" ||
    !Number.isSafeInteger(query.revision) ||
    query.revision < 0 ||
    !Array.isArray(query.colors) ||
    query.colors.length !== slots.length
  )
    throw new Error("Invalid DOCX theme colors");
  const seen = new Set<unknown>();
  for (const value of query.colors) {
    const item = record(value);
    if (
      seen.has(item.slot) ||
      typeof item.reason !== "string" ||
      (item.color === null && !item.reason)
    )
      throw new Error("Invalid DOCX theme color");
    checkDocxThemeColor(item.slot, item.color ?? "000000");
    seen.add(item.slot);
  }
  return value as DocxThemeColors;
}
