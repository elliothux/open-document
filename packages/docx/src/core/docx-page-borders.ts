import { record } from "@open-document/wasm/abi/validation";

export const wordBorderThemeSlots = [
  "dark1",
  "light1",
  "dark2",
  "light2",
  "accent1",
  "accent2",
  "accent3",
  "accent4",
  "accent5",
  "accent6",
  "hyperlink",
  "followedHyperlink",
  "text1",
  "text2",
  "background1",
  "background2",
] as const;

export interface DocxPageBorder {
  side: "top" | "left" | "bottom" | "right";
  style: "single" | "double" | "dashed" | "dotted";
  /** Effective RGB in queries; a fixed color when themeColor is null. */
  color: string;
  /** Native theme slot, or null for a fixed RGB color. */
  themeColor: (typeof wordBorderThemeSlots)[number] | null;
  width: number;
  space: number;
}
export interface DocxPageBorders {
  offsetFrom: "page" | "text";
  display: "allPages" | "firstPage" | "notFirstPage";
  zOrder: "front" | "back";
  sides: DocxPageBorder[];
}
export function checkPageBorders(value: unknown): void {
  if (value === null) return;
  const borders = record(value);
  if (
    typeof borders.offsetFrom !== "string" ||
    !["page", "text"].includes(borders.offsetFrom) ||
    typeof borders.display !== "string" ||
    !["allPages", "firstPage", "notFirstPage"].includes(borders.display) ||
    typeof borders.zOrder !== "string" ||
    !["front", "back"].includes(borders.zOrder) ||
    Object.keys(borders).some(
      (key) => !["offsetFrom", "display", "zOrder", "sides"].includes(key),
    ) ||
    !Array.isArray(borders.sides) ||
    borders.sides.length > 4
  )
    throw new Error("Invalid DOCX page borders");
  const seen = new Set<string>();
  for (const value of borders.sides) {
    const side = record(value);
    if (
      typeof side.side !== "string" ||
      !["top", "left", "bottom", "right"].includes(side.side) ||
      (side.style !== "single" &&
        side.style !== "double" &&
        side.style !== "dashed" &&
        side.style !== "dotted") ||
      seen.has(side.side) ||
      typeof side.color !== "string" ||
      !/^[0-9a-f]{6}$/iu.test(side.color) ||
      (side.themeColor !== null &&
        (typeof side.themeColor !== "string" ||
          !wordBorderThemeSlots.some((slot) => slot === side.themeColor))) ||
      typeof side.width !== "number" ||
      !(side.width >= 0.25 && side.width <= 12) ||
      !Number.isInteger(side.width * 8) ||
      typeof side.space !== "number" ||
      !Number.isInteger(side.space) ||
      side.space < 0 ||
      side.space > 31 ||
      Object.keys(side).some(
        (key) =>
          !["side", "style", "color", "themeColor", "width", "space"].includes(
            key,
          ),
      )
    )
      throw new Error("Invalid DOCX page border side");
    seen.add(side.side);
  }
}
