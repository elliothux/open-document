import { record } from "./validation.js";
import { checkDocxCellMargins, type DocxCellMargins } from "./docx-table.js";
import { isListReference, type DocxListReference } from "./docx-list.js";

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

export interface DocxPageSetup {
  width: number;
  height: number;
  top: number;
  right: number;
  bottom: number;
  left: number;
  /** Rotates dimensions and margins in core when the requested orientation differs. */
  orientation?: "portrait" | "landscape";
}

export interface DocxPageSettings {
  revision: number;
  page: DocxPageSetup | null;
  reason: string;
}

export function checkPageSetup(value: DocxPageSetup): void {
  const page = record(value);
  const fields = ["width", "height", "top", "right", "bottom", "left"];
  if (
    !Object.keys(page).every(
      (key) => fields.includes(key) || key === "orientation",
    ) ||
    (value.orientation !== undefined &&
      !["portrait", "landscape"].includes(value.orientation)) ||
    !fields.every(
      (key) =>
        typeof page[key] === "number" &&
        Number.isFinite(page[key]) &&
        Number(page[key]) >= 0 &&
        Number(page[key]) <= 14400 &&
        Number.isInteger(Number(page[key]) * 20),
    ) ||
    value.width < 36 ||
    value.height < 36 ||
    value.width - value.left - value.right < 12 ||
    value.height - value.top - value.bottom < 12
  )
    throw new Error("Invalid DOCX page dimensions or margins");
}

export function docxPageSettings(value: unknown): DocxPageSettings {
  const result = record(value);
  if (
    !Number.isSafeInteger(result.revision) ||
    Number(result.revision) < 0 ||
    typeof result.reason !== "string"
  )
    throw new Error("Invalid DOCX page settings");
  if (result.page === null) {
    if (!result.reason) throw new Error("Missing page setup reason");
    return {
      revision: Number(result.revision),
      page: null,
      reason: result.reason,
    };
  }
  const page = record(result.page);
  const setup: DocxPageSetup = {
    width: Number(page.width),
    height: Number(page.height),
    top: Number(page.top),
    right: Number(page.right),
    bottom: Number(page.bottom),
    left: Number(page.left),
  };
  if (
    Object.keys(page).length !== 6 ||
    !Object.values(page).every((value) => typeof value === "number") ||
    result.reason
  )
    throw new Error("Invalid DOCX page settings");
  checkPageSetup(setup);
  return { revision: Number(result.revision), page: setup, reason: "" };
}

/** Omitted metadata is retained; null basedOn removes the direct base reference. */
export interface DocxStyleUpdate extends CopiedFormat {
  name?: string;
  basedOn?: string | null;
  reset?: true;
}

export interface DocxStyleCreation {
  name: string;
  kind: "paragraph" | "character";
  basedOn?: string;
}

export function checkStyleCreation(style: DocxStyleCreation): void {
  const fields = record(style);
  if (
    !Object.keys(fields).every((key) =>
      ["name", "kind", "basedOn"].includes(key),
    ) ||
    !["paragraph", "character"].includes(style.kind) ||
    (style.basedOn !== undefined &&
      (typeof style.basedOn !== "string" ||
        !style.basedOn ||
        style.basedOn.length > 200))
  )
    throw new Error("Invalid style creation");
  checkStyleUpdate({ character: {}, paragraph: {}, name: style.name });
  if (typeof style.name !== "string") throw new Error("Invalid style name");
}

export function checkStyleUpdate(format: DocxStyleUpdate): void {
  const fields = record(format);
  if (
    !Object.keys(fields).every((key) =>
      ["character", "paragraph", "name", "basedOn", "reset"].includes(key),
    )
  )
    throw new Error("Invalid style update");
  copiedFormat({ character: format.character, paragraph: format.paragraph });
  if (
    format.reset !== undefined &&
    (format.reset !== true ||
      format.name !== undefined ||
      format.basedOn !== undefined ||
      Object.keys(format.character).length > 0 ||
      Object.keys(format.paragraph).length > 0)
  )
    throw new Error("Style reset cannot include other changes");
  if (
    format.character.style !== undefined ||
    format.paragraph.style !== undefined
  )
    throw new Error("Style updates cannot change style references");
  if (
    format.name !== undefined &&
    (typeof format.name !== "string" ||
      !format.name.trim() ||
      format.name.length > 200)
  )
    throw new Error("Invalid style name");
  if (
    format.basedOn !== undefined &&
    format.basedOn !== null &&
    (typeof format.basedOn !== "string" ||
      !format.basedOn ||
      format.basedOn.length > 200)
  )
    throw new Error("Invalid base style");
}

export type FormatValue<T> =
  | { kind: "value"; value: T }
  | { kind: "mixed" }
  | { kind: "unavailable"; reason: string };
export interface CharacterFormatPatch {
  style?: string | null;
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

export function checkDefaultTabStop(value: unknown): void {
  if (
    value !== null &&
    (typeof value !== "number" ||
      value < 0 ||
      value > 1584 ||
      !Number.isInteger(value * 20))
  )
    throw new Error("Invalid default tab interval");
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
  rtl?: boolean | null;
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
  table: {
    id: number;
    row: number;
    columns: number;
    width: number;
    rowHeight: number;
    rows: number;
    headerRows: number;
    cellFill: string | null;
    cellVerticalAlign: "top" | "center" | "bottom";
    cellMargins: DocxCellMargins;
    tableMargins: DocxCellMargins;
    align: "left" | "center" | "right";
    maxWidth: number;
    maxRowHeight: number;
  } | null;
  list: FormatValue<DocxListReference | null>;
  character: {
    style: FormatValue<string>;
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
    rtl: FormatValue<boolean>;
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
        rtl: "boolean",
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
        style: "string",
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
  const table = record(result.table);
  if (result.table !== null) {
    checkDocxCellMargins(table.cellMargins);
    checkDocxCellMargins(table.tableMargins);
    if (!["left", "center", "right"].includes(String(table.align)))
      throw new Error("Invalid table alignment");
  }
  const field = (value: unknown, type: string): boolean => {
    const item = record(value);
    if (item.kind === "value" && type === "list")
      return item.value === null || isListReference(item.value);
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
    (result.table !== null &&
      (!["id", "row", "columns", "rows", "headerRows"].every(
        (key) =>
          Number.isSafeInteger(table[key]) &&
          Number(table[key]) >= 0 &&
          Number(table[key]) <= 2147483647,
      ) ||
        Number(table.columns) < 1 ||
        Number(table.rows) < 1 ||
        Number(table.row) >= Number(table.rows) ||
        Number(table.headerRows) > Number(table.rows) ||
        !["top", "center", "bottom"].includes(
          String(table.cellVerticalAlign),
        ) ||
        (table.cellFill !== null &&
          (typeof table.cellFill !== "string" ||
            !/^[0-9a-f]{6}$/i.test(table.cellFill))) ||
        !["width", "rowHeight", "maxWidth", "maxRowHeight"].every(
          (key) =>
            typeof table[key] === "number" &&
            Number.isFinite(table[key]) &&
            Number(table[key]) >= 0,
        ))) ||
    !field(result.list, "list") ||
    !["style", "family", "color", "highlight", "vertAlign"].every((key) =>
      field(character[key], "string"),
    ) ||
    !field(character.size, "number") ||
    !["bold", "italic", "underline", "strike"].every((key) =>
      field(character[key], "boolean"),
    ) ||
    !field(paragraph.style, "string") ||
    !field(paragraph.align, "string") ||
    !field(paragraph.rtl, "boolean") ||
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

export interface DocxStyleCatalog {
  revision: number;
  truncated: boolean;
  styles: {
    id: string;
    name: string;
    reason: string;
    basedOn: string;
    canDelete: boolean;
    canReset: boolean;
    linked: boolean;
  }[];
}

export function docxStyleCatalog(value: unknown): DocxStyleCatalog {
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
        typeof style.reason === "string" &&
        typeof style.basedOn === "string" &&
        typeof style.canDelete === "boolean" &&
        typeof style.canReset === "boolean" &&
        typeof style.linked === "boolean"
      );
    })
  )
    throw new Error("Invalid DOCX style catalog");
  return value as DocxStyleCatalog;
}
