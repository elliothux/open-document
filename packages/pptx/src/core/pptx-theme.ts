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
