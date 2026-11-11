import { record } from "@open-document/wasm/abi/validation";

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
export interface DocxThemeFontEdit {
  kind: "major" | "minor";
  script: "latin" | "ea" | "cs";
  font: string;
}
export interface DocxThemeFonts {
  revision: number;
  fonts: (Omit<DocxThemeFontEdit, "font"> & {
    font: string | null;
    reason: string;
  })[];
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
  if (!Array.isArray(value) || !value.length || value.length > 6)
    throw new Error("Invalid DOCX theme font changes");
  const seen = new Set<string>();
  for (const entry of value) {
    const change = record(entry);
    const key = `${change.kind}:${change.script}`;
    if (
      Object.keys(change).length !== 3 ||
      typeof change.kind !== "string" ||
      !["major", "minor"].includes(change.kind) ||
      typeof change.script !== "string" ||
      !["latin", "ea", "cs"].includes(change.script) ||
      seen.has(key) ||
      (!(change.font === "" && change.script !== "latin") &&
        !fontFamily(change.font))
    )
      throw new Error("Invalid DOCX theme font change");
    seen.add(key);
  }
}
export function checkDocxThemeColor(slot: unknown, color: unknown): void {
  if (
    !slots.some((value) => value === slot) ||
    typeof color !== "string" ||
    !/^[0-9a-f]{6}$/i.test(color)
  )
    throw new Error("Invalid DOCX theme color");
}
