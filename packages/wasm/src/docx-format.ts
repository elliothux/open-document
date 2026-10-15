import { record } from "./validation.js";

/** Uniform effective values captured by the core; mixed properties are omitted. */
export interface CopiedFormat {
  character: CharacterFormatPatch;
  paragraph: ParagraphFormatPatch;
}

export function copiedFormat(value: unknown): CopiedFormat {
  const result = record(value);
  if (Object.keys(result).length !== 2)
    throw new Error("Invalid copied format");
  checkFormatPatch(record(result.character));
  checkFormatPatch(record(result.paragraph), true);
  return value as CopiedFormat;
}

export type FormatValue<T> =
  | { kind: "value"; value: T }
  | { kind: "mixed" }
  | { kind: "unavailable"; reason: string };
export interface CharacterFormatPatch {
  family?: string | null;
  size?: number | null;
  color?: string | null;
  bold?: boolean | null;
  italic?: boolean | null;
  underline?: boolean | null;
  strike?: boolean | null;
  highlight?: HighlightColor | null;
  vertAlign?: "baseline" | "superscript" | "subscript" | null;
}
export const highlightColors = [
  "none",
  "black",
  "blue",
  "cyan",
  "green",
  "magenta",
  "red",
  "yellow",
  "white",
  "darkBlue",
  "darkCyan",
  "darkGreen",
  "darkMagenta",
  "darkRed",
  "darkYellow",
  "darkGray",
  "lightGray",
] as const;
export type HighlightColor = (typeof highlightColors)[number];
export interface TabStop {
  position: number;
  align: "left" | "center" | "right" | "decimal" | "bar";
  leader?: "none" | "dot" | "hyphen" | "underscore" | "heavy" | "middleDot";
}

export function checkTabStops(value: unknown): void {
  if (!Array.isArray(value) || value.length > 64)
    throw new Error("Invalid tab stops");
  let previous = -1;
  for (const entry of value) {
    const stop = record(entry);
    if (
      !Object.keys(stop).every((key) =>
        ["position", "align", "leader"].includes(key),
      ) ||
      typeof stop.position !== "number" ||
      stop.position < 0 ||
      stop.position > 1584 ||
      !Number.isInteger(stop.position * 20) ||
      stop.position <= previous ||
      typeof stop.align !== "string" ||
      !["left", "center", "right", "decimal", "bar"].includes(stop.align) ||
      (stop.leader !== undefined &&
        (typeof stop.leader !== "string" ||
          ![
            "none",
            "dot",
            "hyphen",
            "underscore",
            "heavy",
            "middleDot",
          ].includes(stop.leader))) ||
      (stop.align === "bar" &&
        stop.leader !== undefined &&
        stop.leader !== "none")
    )
      throw new Error("Invalid tab stop");
    previous = stop.position;
  }
}
export interface ParagraphFormatPatch {
  style?: string | null;
  align?: "left" | "center" | "right" | "both" | null;
  before?: number | null;
  after?: number | null;
  left?: number | null;
  right?: number | null;
  first?: number | null;
  /** OOXML units: auto uses 240 per line; exact/atLeast use twips. */
  line?: { rule: "auto" | "exact" | "atLeast"; value: number } | null;
  tabs?: TabStop[] | null;
  pageBreakBefore?: boolean | null;
}
export interface DocxFormatting {
  revision: number;
  reason: string;
  character: {
    family: FormatValue<string>;
    size: FormatValue<number>;
    color: FormatValue<string>;
    bold: FormatValue<boolean>;
    italic: FormatValue<boolean>;
    underline: FormatValue<boolean>;
    strike: FormatValue<boolean>;
    highlight: FormatValue<HighlightColor>;
    vertAlign: FormatValue<"baseline" | "superscript" | "subscript">;
  };
  paragraph: {
    style: FormatValue<string>;
    align: FormatValue<string>;
    before: FormatValue<number>;
    after: FormatValue<number>;
    left: FormatValue<number>;
    right: FormatValue<number>;
    first: FormatValue<number>;
    line: FormatValue<{ rule: "auto" | "exact" | "atLeast"; value: number }>;
    tabs: FormatValue<TabStop[]>;
    pageBreakBefore: FormatValue<boolean>;
  };
}
export function checkFormatPatch(
  format: CharacterFormatPatch | ParagraphFormatPatch,
  paragraph = false,
): void {
  const fields = paragraph
    ? {
        style: "string",
        align: "string",
        before: "number",
        after: "number",
        left: "number",
        right: "number",
        first: "number",
        line: "object",
        tabs: "object",
        pageBreakBefore: "boolean",
      }
    : {
        family: "string",
        size: "number",
        color: "string",
        bold: "boolean",
        italic: "boolean",
        underline: "boolean",
        strike: "boolean",
        highlight: "string",
        vertAlign: "string",
      };
  for (const [key, value] of Object.entries(record(format))) {
    if (paragraph && key === "tabs" && value !== null && value !== undefined)
      checkTabStops(value);
    if (paragraph && key === "line" && value !== null && value !== undefined) {
      const spacing = record(value);
      if (!lineSpacing(spacing) || Object.keys(spacing).length !== 2)
        throw new Error("Invalid line spacing");
    }
    if (
      !Object.hasOwn(fields, key) ||
      (value !== null &&
        value !== undefined &&
        (typeof value !== Reflect.get(fields, key) ||
          (typeof value === "number" && !Number.isFinite(value))))
    )
      throw new Error("Invalid formatting property: " + key);
  }
}
function lineSpacing(value: unknown): boolean {
  const spacing = record(value);
  return (
    (spacing.rule === "auto" ||
      spacing.rule === "exact" ||
      spacing.rule === "atLeast") &&
    typeof spacing.value === "number" &&
    Number.isFinite(spacing.value)
  );
}
export function docxFormatting(value: unknown): DocxFormatting {
  const result = record(value),
    character = record(result.character),
    paragraph = record(result.paragraph);
  const field = (value: unknown, type: string): boolean => {
    const item = record(value);
    if (item.kind === "value" && type === "tabs") {
      checkTabStops(item.value);
      return true;
    }
    return (
      item.kind === "mixed" ||
      (item.kind === "unavailable" && typeof item.reason === "string") ||
      (item.kind === "value" &&
        typeof item.value === type &&
        (type !== "number" || Number.isFinite(item.value)) &&
        (type !== "object" || lineSpacing(item.value)))
    );
  };
  if (
    !Number.isSafeInteger(result.revision) ||
    Number(result.revision) < 0 ||
    typeof result.reason !== "string" ||
    !["family", "color", "highlight", "vertAlign"].every((key) =>
      field(character[key], "string"),
    ) ||
    !field(character.size, "number") ||
    !["bold", "italic", "underline", "strike"].every((key) =>
      field(character[key], "boolean"),
    ) ||
    !field(paragraph.style, "string") ||
    !field(paragraph.align, "string") ||
    !["before", "after", "left", "right", "first"].every((key) =>
      field(paragraph[key], "number"),
    ) ||
    !field(paragraph.pageBreakBefore, "boolean") ||
    !field(paragraph.line, "object") ||
    !field(paragraph.tabs, "tabs")
  )
    throw new Error("Invalid DOCX formatting returned by Wasm");
  return value as DocxFormatting;
}

export interface ParagraphStyleCatalog {
  revision: number;
  truncated: boolean;
  styles: { id: string; name: string; reason: string }[];
}

export function paragraphStyleCatalog(value: unknown): ParagraphStyleCatalog {
  const catalog = record(value);
  if (
    !Number.isSafeInteger(catalog.revision) ||
    Number(catalog.revision) < 0 ||
    typeof catalog.truncated !== "boolean" ||
    !Array.isArray(catalog.styles) ||
    catalog.styles.length > 1024 ||
    !catalog.styles.every((value) => {
      const style = record(value);
      return (
        typeof style.id === "string" &&
        typeof style.name === "string" &&
        typeof style.reason === "string"
      );
    })
  )
    throw new Error("Invalid paragraph style catalog");
  return value as ParagraphStyleCatalog;
}
