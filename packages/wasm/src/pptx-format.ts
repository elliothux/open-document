import { record } from "./validation.js";

export interface PptxTextFormat {
  font?: string;
  size?: number;
  bold?: boolean;
  italic?: boolean;
  color?: string;
  underline?: boolean;
  strike?: boolean;
  highlight?: string;
}
export interface PptxFormatting {
  font: string | null;
  size: number | null;
  bold: boolean | null;
  italic: boolean | null;
  color: string | null;
  underline: boolean | null;
  strike: boolean | null;
  highlight: string | null;
  alignment: "left" | "center" | "right" | null;
  reason: string;
}

export interface PptxTextSpacing {
  unit: "point" | "percent";
  value: number;
}
export interface PptxParagraphFormat {
  left?: number;
  right?: number;
  first?: number;
  before?: PptxTextSpacing;
  after?: PptxTextSpacing;
  line?: PptxTextSpacing;
}
export interface PptxParagraphFormatting {
  left: number | null;
  right: number | null;
  first: number | null;
  before: PptxTextSpacing | null;
  after: PptxTextSpacing | null;
  line: PptxTextSpacing | null;
  reason: string;
}

function paragraphProperty(key: string, value: unknown): boolean {
  if (["left", "right", "first"].includes(key))
    return (
      typeof value === "number" &&
      Number.isFinite(value) &&
      value >= (key === "first" ? -4032 : 0) &&
      value <= 4032
    );
  if (!["before", "after", "line"].includes(key)) return false;
  const spacing = record(value);
  const factor = spacing.unit === "point" ? 100 : 1000;
  return (
    Object.keys(spacing).every((key) => key === "unit" || key === "value") &&
    (spacing.unit === "point" || spacing.unit === "percent") &&
    typeof spacing.value === "number" &&
    Number.isFinite(spacing.value) &&
    spacing.value >= (key === "line" ? 1 / factor : 0) &&
    spacing.value <= (spacing.unit === "point" ? 1584 : 1000)
  );
}

export function checkPptxParagraphFormat(value: unknown): void {
  const format = record(value);
  if (
    !Object.keys(format).length ||
    Object.entries(format).some(
      ([key, value]) => !paragraphProperty(key, value),
    )
  )
    throw new Error("Invalid paragraph format");
}

export function checkPptxParagraphFormatting(value: unknown): void {
  const format = record(value);
  if (
    typeof format.reason !== "string" ||
    ["left", "right", "first", "before", "after", "line"].some(
      (key) => format[key] !== null && !paragraphProperty(key, format[key]),
    )
  )
    throw new Error("Invalid paragraph format query");
}

function property(key: string, value: unknown): boolean {
  switch (key) {
    case "font":
      return (
        typeof value === "string" &&
        value.trim().length > 0 &&
        value.length <= 200 &&
        !value.startsWith("+") &&
        !value.includes("|") &&
        !Array.from(value).some((character) => {
          const code = character.charCodeAt(0);
          return (code < 32 && code !== 9) || code === 65534 || code === 65535;
        }) &&
        value.isWellFormed()
      );
    case "size":
      return (
        typeof value === "number" &&
        Number.isFinite(value) &&
        value >= 1 &&
        value <= 1024
      );
    case "bold":
    case "italic":
    case "underline":
    case "strike":
      return typeof value === "boolean";
    case "highlight":
      return (
        typeof value === "string" &&
        (value === "" || /^[0-9a-f]{6}$/i.test(value))
      );
    case "color":
      return typeof value === "string" && /^[0-9a-f]{6}$/i.test(value);
    default:
      return false;
  }
}

export function checkPptxTextFormat(value: unknown): void {
  const format = record(value);
  if (
    !Object.keys(format).length ||
    Object.entries(format).some(([key, value]) => !property(key, value))
  )
    throw new Error("Invalid text format");
}

export function checkPptxFormatting(value: unknown): void {
  const format = record(value);
  if (
    typeof format.reason !== "string" ||
    (format.alignment !== null &&
      !["left", "center", "right"].includes(String(format.alignment))) ||
    [
      "font",
      "size",
      "bold",
      "italic",
      "color",
      "underline",
      "strike",
      "highlight",
    ].some((key) => format[key] !== null && !property(key, format[key]))
  )
    throw new Error("Invalid text formatting query");
}
