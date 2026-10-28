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
export type PptxThemeSlot = (typeof slots)[number];
export interface PptxThemeColor {
  slot: PptxThemeSlot;
  color: string | null;
  reason: string;
}
export interface PptxThemeFont {
  kind: "major" | "minor";
  script: string;
  font: string | null;
  reason: string;
}
export function checkPptxThemeFont(value: unknown): void {
  const change = record(value);
  if (
    !["major", "minor"].includes(String(change.kind)) ||
    typeof change.kind !== "string" ||
    typeof change.script !== "string" ||
    !/^(latin|ea|cs|[A-Z][a-z]{3})$/.test(change.script) ||
    typeof change.font !== "string" ||
    change.font.length > 200 ||
    !change.font.isWellFormed() ||
    Array.from(change.font).some((character) => {
      const code = character.codePointAt(0)!;
      return (
        character === "|" ||
        (code < 32 && code !== 9) ||
        code === 65534 ||
        code === 65535
      );
    }) ||
    change.font.startsWith("+") ||
    (change.font !== "" && !change.font.trim()) ||
    (change.script === "latin" && !change.font) ||
    Object.keys(change).some(
      (key) => !["action", "kind", "script", "font"].includes(key),
    )
  )
    throw new Error("Invalid theme font");
}
export function pptxThemeFonts(value: unknown): PptxThemeFont[] {
  if (!Array.isArray(value) || value.length < 6 || value.length > 256)
    throw new Error("Invalid theme fonts");
  const seen = new Set<string>();
  for (const item of value) {
    const font = record(item);
    checkPptxThemeFont({
      kind: font.kind,
      script: font.script,
      font: font.font === null || font.font === "" ? "Default" : font.font,
    });
    const key = `${font.kind}:${font.script}`;
    if (
      seen.has(key) ||
      typeof font.reason !== "string" ||
      (font.font !== null && typeof font.font !== "string")
    )
      throw new Error("Invalid theme font slot");
    seen.add(key);
  }
  for (const kind of ["major", "minor"])
    for (const script of ["latin", "ea", "cs"])
      if (!seen.has(`${kind}:${script}`))
        throw new Error("Missing theme font slot");
  return value as PptxThemeFont[];
}
export function checkPptxThemeColor(value: unknown): void {
  const change = record(value);
  if (
    typeof change.slot !== "string" ||
    !slots.some((slot) => slot === change.slot) ||
    typeof change.color !== "string" ||
    !/^[0-9a-f]{6}$/i.test(change.color) ||
    Object.keys(change).some(
      (key) => !["action", "slot", "color"].includes(key),
    )
  )
    throw new Error("Invalid theme color");
}
export function pptxThemeColors(value: unknown): PptxThemeColor[] {
  if (!Array.isArray(value) || value.length !== slots.length)
    throw new Error("Invalid theme palette");
  const seen = new Set<string>();
  for (const item of value) {
    const color = record(item);
    checkPptxThemeColor({ slot: color.slot, color: color.color ?? "000000" });
    if (
      seen.has(String(color.slot)) ||
      typeof color.reason !== "string" ||
      (color.color !== null && typeof color.color !== "string")
    )
      throw new Error("Invalid theme palette color");
    seen.add(String(color.slot));
  }
  return value as PptxThemeColor[];
}
