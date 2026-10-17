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
  script?: "baseline" | "superscript" | "subscript";
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
  script: "baseline" | "superscript" | "subscript" | null;
  alignment: "left" | "center" | "right" | "justify" | null;
  reason: string;
}

export interface PptxTextSpacing {
  unit: "point" | "percent";
  value: number;
}
const numberingFormats = [
  "arabicPeriod",
  "arabicParenBoth",
  "arabicParenR",
  "arabicPlain",
  "alphaLcPeriod",
  "alphaLcParenBoth",
  "alphaLcParenR",
  "alphaUcPeriod",
  "alphaUcParenBoth",
  "alphaUcParenR",
  "romanLcPeriod",
  "romanLcParenBoth",
  "romanLcParenR",
  "romanUcPeriod",
  "romanUcParenBoth",
  "romanUcParenR",
] as const;

export type PptxListFormat =
  | { kind: "none" }
  | { kind: "bullet"; value: string }
  | {
      kind: "number";
      value: (typeof numberingFormats)[number];
      start: number;
    };
export interface PptxParagraphFormat {
  left?: number;
  right?: number;
  first?: number;
  before?: PptxTextSpacing;
  after?: PptxTextSpacing;
  line?: PptxTextSpacing;
  list?: PptxListFormat;
  level?: number;
  rtl?: boolean;
  listFont?: string | null;
  listSize?: PptxTextSpacing | null;
  listColor?: string | null;
}
export interface PptxParagraphFormatting {
  left: number | null;
  right: number | null;
  first: number | null;
  before: PptxTextSpacing | null;
  after: PptxTextSpacing | null;
  line: PptxTextSpacing | null;
  list: PptxListFormat | null;
  level: number | null;
  rtl: boolean | null;
  listFont: string | null;
  listSize: PptxTextSpacing | null;
  listColor: string | null;
  reason: string;
}

function paragraphProperty(key: string, value: unknown): boolean {
  if (key === "listFont" || key === "listColor")
    return (
      value === null || property(key === "listFont" ? "font" : "color", value)
    );
  if (key === "listSize") {
    if (value === null) return true;
    const size = record(value);
    return (
      Object.keys(size).length === 2 &&
      (size.unit === "point" || size.unit === "percent") &&
      typeof size.value === "number" &&
      Number.isFinite(size.value) &&
      size.value >= 1 &&
      size.value <= (size.unit === "point" ? 1024 : 400)
    );
  }
  if (key === "rtl") return typeof value === "boolean";
  if (key === "level")
    return (
      typeof value === "number" &&
      Number.isInteger(value) &&
      value >= 0 &&
      value <= 8
    );
  if (key === "list") {
    const list = record(value),
      keys = Object.keys(list);
    if (list.kind === "none") return keys.length === 1;
    if (list.kind === "bullet")
      return (
        keys.length === 2 &&
        typeof list.value === "string" &&
        list.value.length <= 16 &&
        list.value.isWellFormed() &&
        !Array.from(list.value).some((character) => {
          const code = character.charCodeAt(0);
          return code <= 32 || [127, 8232, 8233, 65534, 65535].includes(code);
        }) &&
        Array.from(
          new Intl.Segmenter("und", { granularity: "grapheme" }).segment(
            list.value,
          ),
        ).length === 1
      );
    return (
      list.kind === "number" &&
      keys.length === 3 &&
      typeof list.value === "string" &&
      numberingFormats.some((value) => value === list.value) &&
      typeof list.start === "number" &&
      Number.isInteger(list.start) &&
      list.start >= 1 &&
      list.start <= 32767
    );
  }
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
    [
      "left",
      "right",
      "first",
      "before",
      "after",
      "line",
      "list",
      "level",
      "rtl",
      "listFont",
      "listSize",
      "listColor",
    ].some(
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
    case "script":
      return (
        typeof value === "string" &&
        ["baseline", "superscript", "subscript"].includes(value)
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
      (typeof format.alignment !== "string" ||
        !["left", "center", "right", "justify"].includes(format.alignment))) ||
    [
      "font",
      "size",
      "bold",
      "italic",
      "color",
      "underline",
      "strike",
      "highlight",
      "script",
    ].some((key) => format[key] !== null && !property(key, format[key]))
  )
    throw new Error("Invalid text formatting query");
}
