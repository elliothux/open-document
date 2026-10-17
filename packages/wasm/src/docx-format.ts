import { record, arrayOf } from "./validation.js";
import type { DocxSelection } from "./docx-hit.js";
import { isDocxSelection } from "./docx-search.js";
import {
  checkDocxCellMargins,
  checkDocxBorders,
  type DocxCellMargins,
  type DocxCellBorders,
  type DocxTableBorders,
} from "./docx-table.js";
import {
  isListReference,
  listFormats,
  type ListFormat,
  type DocxListReference,
} from "./docx-list.js";

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
  background: { color: string | null; reason: string };
  borders: { value: DocxPageBorders; reason: string };
  numbering: { value: DocxPageNumbering | null; reason: string };
}

export interface DocxPageNumbering {
  start: number;
  format: Exclude<ListFormat, "bullet">;
}
export function checkPageNumbering(value: unknown): void {
  if (value === null) return;
  const numbering = record(value);
  if (
    Object.keys(numbering).length !== 2 ||
    Object.keys(numbering).some((key) => !["start", "format"].includes(key)) ||
    typeof numbering.start !== "number" ||
    !Number.isInteger(numbering.start) ||
    numbering.start < 0 ||
    numbering.start > 4294967295 ||
    typeof numbering.format !== "string" ||
    numbering.format === "bullet" ||
    !listFormats.some((format) => format === numbering.format)
  )
    throw new Error("Invalid DOCX page numbering");
}

export interface DocxPageBorder {
  side: "top" | "left" | "bottom" | "right";
  color: string;
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
      seen.has(side.side) ||
      typeof side.color !== "string" ||
      !/^[0-9a-f]{6}$/iu.test(side.color) ||
      typeof side.width !== "number" ||
      !(side.width >= 0.25 && side.width <= 12) ||
      !Number.isInteger(side.width * 8) ||
      typeof side.space !== "number" ||
      !Number.isInteger(side.space) ||
      side.space < 0 ||
      side.space > 31 ||
      Object.keys(side).some(
        (key) => !["side", "color", "width", "space"].includes(key),
      )
    )
      throw new Error("Invalid DOCX page border side");
    seen.add(side.side);
  }
}

export function checkPageBackground(color: unknown): void {
  if (
    color !== null &&
    (typeof color !== "string" || !/^[0-9a-f]{6}$/iu.test(color))
  )
    throw new Error("Invalid DOCX page background");
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
  const numbering = record(result.numbering);
  checkPageNumbering(numbering.value);
  if (
    typeof numbering.reason !== "string" ||
    (numbering.value === null) !== !!numbering.reason
  )
    throw new Error("Invalid DOCX page numbering settings");
  const numbers = {
    value: numbering.value as DocxPageNumbering | null,
    reason: numbering.reason,
  };
  const border = record(result.borders);
  checkPageBorders(border.value);
  if (border.value === null || typeof border.reason !== "string")
    throw new Error("Invalid DOCX page border settings");
  const borders = {
    value: border.value as DocxPageBorders,
    reason: border.reason,
  };
  const background = record(result.background);
  checkPageBackground(background.color);
  if (
    typeof background.reason !== "string" ||
    (background.reason && background.color !== null)
  )
    throw new Error("Invalid DOCX page background settings");
  const paint = {
    color: background.color === null ? null : String(background.color),
    reason: background.reason,
  };
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
      background: paint,
      borders,
      numbering: numbers,
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
  return {
    revision: Number(result.revision),
    page: setup,
    reason: "",
    background: paint,
    borders,
    numbering: numbers,
  };
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
  keepLines?: boolean | null;
  keepNext?: boolean | null;
  widowControl?: boolean | null;
}
export interface DocxFormatting {
  revision: number;
  reason: string;
  hyperlink: { target: string | null; mixed: boolean; reason: string };
  table: {
    autoFit: boolean;
    id: number;
    row: number;
    columns: number;
    column: number;
    columnWidths: number[];
    width: number;
    rowHeight: number;
    rowHeightRule: "atLeast" | "exact";
    rows: number;
    headerRows: number;
    rowSplit: boolean;
    cellFill: string | null;
    cellVerticalAlign: "top" | "center" | "bottom";
    cellMargins: DocxCellMargins;
    cellBorders: DocxCellBorders;
    tableBorders: DocxTableBorders;
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
    keepLines: FormatValue<boolean>;
    keepNext: FormatValue<boolean>;
    widowControl: FormatValue<boolean>;
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
        keepLines: "boolean",
        keepNext: "boolean",
        widowControl: "boolean",
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
  const hyperlink = record(result.hyperlink);
  checkDocxHyperlink(hyperlink.target);
  if (
    typeof hyperlink.mixed !== "boolean" ||
    typeof hyperlink.reason !== "string" ||
    (hyperlink.mixed && hyperlink.target !== null)
  )
    throw new Error("Invalid DOCX hyperlink query");
  const table = record(result.table ?? {});
  if (result.table !== null) {
    for (const [name, whole] of [
      ["cellBorders", false],
      ["tableBorders", true],
    ] as const) {
      checkDocxBorders(table[name], whole);
      if (Object.keys(record(table[name])).length !== (whole ? 6 : 4))
        throw new Error("Incomplete border query");
    }
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
      (typeof table.autoFit !== "boolean" ||
        typeof table.rowSplit !== "boolean" ||
        !["id", "row", "column", "columns", "rows", "headerRows"].every(
          (key) =>
            Number.isSafeInteger(table[key]) &&
            Number(table[key]) >= 0 &&
            Number(table[key]) <= 2147483647,
        ) ||
        Number(table.columns) < 1 ||
        Number(table.rows) < 1 ||
        Number(table.row) >= Number(table.rows) ||
        Number(table.column) >= Number(table.columns) ||
        !Array.isArray(table.columnWidths) ||
        table.columnWidths.length !== Number(table.columns) ||
        !table.columnWidths.every(
          (width: unknown) =>
            typeof width === "number" && Number.isFinite(width) && width > 0,
        ) ||
        Number(table.headerRows) > Number(table.rows) ||
        !["atLeast", "exact"].includes(String(table.rowHeightRule)) ||
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
    !field(paragraph.keepLines, "boolean") ||
    !field(paragraph.keepNext, "boolean") ||
    !field(paragraph.widowControl, "boolean") ||
    !field(paragraph.line, "object") ||
    !field(paragraph.tabs, "tabs")
  )
    throw new Error("Invalid DOCX formatting returned by Wasm");
  return value as DocxFormatting;
}

export function checkDocxHyperlink(target: unknown, text?: unknown): void {
  if (
    target !== null &&
    (typeof target !== "string" ||
      !target.isWellFormed() ||
      target.length > 2048 ||
      (!/^(https?:\/\/|mailto:).+/i.test(target) &&
        !/^#[A-Za-z_][A-Za-z0-9_]{0,39}$/.test(target)) ||
      /\s/u.test(target) ||
      Array.from(target).some(
        (c) =>
          c.charCodeAt(0) <= 32 ||
          c.charCodeAt(0) === 127 ||
          c.charCodeAt(0) >= 65534 ||
          c === "\\",
      ))
  )
    throw new Error("Invalid DOCX hyperlink target");
  if (
    text !== undefined &&
    (target === null ||
      typeof text !== "string" ||
      !text ||
      !text.isWellFormed() ||
      text.length > 65536 ||
      Array.from(text).some(
        (c) =>
          c.charCodeAt(0) <= 31 || c === "\u2028" || c.charCodeAt(0) >= 65534,
      ))
  )
    throw new Error("Invalid DOCX hyperlink display text");
}

export interface EditState {
  revision: number;
  defaultTabStop: number;
  compositionId: number | null;
  pictureResizeId: number | null;
  selection: DocxSelection | null;
  canUndo: boolean;
  canRedo: boolean;
  affectedParagraphs: number[];
  historyBytes: number;
  historyEntries: number;
  historyEntryLimit: number;
  historyByteLimit: number;
  commandLimit: number;
  formatting: DocxFormatting | null;
}

export interface CreatedDocxStyle {
  id: string;
  state: EditState;
}

export function createdDocxStyle(value: unknown): CreatedDocxStyle {
  const result = record(value);
  if (typeof result.id !== "string" || !result.id || result.id.length > 200)
    throw new Error("Invalid created style identity");
  return { id: result.id, state: editState(result.state) };
}

export function editState(value: unknown): EditState {
  const object = record(value);
  const integer = (value: unknown): boolean =>
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
  if (object.formatting !== null) docxFormatting(object.formatting);
  if (
    ![
      "revision",
      "historyBytes",
      "historyEntries",
      "historyEntryLimit",
      "historyByteLimit",
      "commandLimit",
    ].every((key) => integer(object[key])) ||
    (object.compositionId !== null &&
      (!integer(object.compositionId) || Number(object.compositionId) === 0)) ||
    (object.pictureResizeId !== null &&
      (!integer(object.pictureResizeId) ||
        Number(object.pictureResizeId) === 0 ||
        Number(object.pictureResizeId) > 2147483647 ||
        object.compositionId !== null)) ||
    typeof object.canUndo !== "boolean" ||
    typeof object.canRedo !== "boolean" ||
    typeof object.defaultTabStop !== "number" ||
    object.defaultTabStop < 0 ||
    object.defaultTabStop > 1584 ||
    !Number.isInteger(object.defaultTabStop * 20) ||
    !arrayOf(object.affectedParagraphs, integer) ||
    (object.selection !== null && !isDocxSelection(object.selection))
  )
    throw new Error("Invalid DOCX editing state returned by Wasm");
  return value as EditState;
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
