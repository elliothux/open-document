import { record } from "@open-document/wasm/abi/validation";
import {
  docxHyperlinkTargetUnits,
  docxNumberingStartMax,
  docxTextCommandUnits,
  tabStopCount,
} from "@open-document/wasm/engine-source";
import type { DocxColumns } from "./docx-columns.js";
import { type DocxCellSelection } from "./docx-cell-selection.js";
export { checkDocxColumns, type DocxColumns } from "./docx-columns.js";
import type { DocxSelection } from "./docx-hit.js";
import {
  type DocxCellMargins,
  type DocxCellBorders,
  type DocxTableBorders,
} from "./docx-table.js";
import {
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

import type { DocxPageSetup } from "./docx-sections.js";
export {
  checkPageSection,
  checkPageSetup,
  type DocxPageSetup,
} from "./docx-sections.js";

export interface DocxPageSettings {
  revision: number;
  sectionCount: number;
  page: DocxPageSetup | null;
  reason: string;
  background: { color: string | null; reason: string };
  borders: { value: DocxPageBorders; reason: string };
  numbering: { value: DocxPageNumbering | null; reason: string };
  columns: {
    value: DocxColumns | null;
    reason: string;
    availableWidth: number | null;
  };
}

export interface DocxPageNumbering {
  /** Null continues the preceding section, or starts at 1 in the first section. */
  start: number | null;
  format: Exclude<ListFormat, "bullet">;
}
export function checkPageNumbering(value: unknown): void {
  if (value === null) return;
  const numbering = record(value);
  if (
    Object.keys(numbering).length !== 2 ||
    Object.keys(numbering).some((key) => !["start", "format"].includes(key)) ||
    (numbering.start !== null &&
      (typeof numbering.start !== "number" ||
        !Number.isInteger(numbering.start) ||
        numbering.start < 0 ||
        numbering.start > docxNumberingStartMax)) ||
    typeof numbering.format !== "string" ||
    numbering.format === "bullet" ||
    !listFormats.some((format) => format === numbering.format)
  )
    throw new Error("Invalid DOCX page numbering");
}

import type { DocxPageBorders } from "./docx-page-borders.js";
export {
  checkPageBorders,
  type DocxPageBorder,
  type DocxPageBorders,
} from "./docx-page-borders.js";

export function checkPageBackground(color: unknown): void {
  if (
    color !== null &&
    (typeof color !== "string" || !/^[0-9a-f]{6}$/iu.test(color))
  )
    throw new Error("Invalid DOCX page background");
}

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
  spacing?: number | null;
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
  if (!Array.isArray(value) || value.length > tabStopCount)
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
  inputReason: string;
  fontReason: string;
  paragraphReason: string;
  cellSelection: DocxCellSelection;
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
    spacing: FormatValue<number>;
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
        spacing: "number",
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
export function checkDocxHyperlink(target: unknown, text?: unknown): void {
  if (
    target !== null &&
    (typeof target !== "string" ||
      !target.isWellFormed() ||
      target.length > docxHyperlinkTargetUnits ||
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
      text.length > docxTextCommandUnits ||
      Array.from(text).some(
        (c) =>
          c.charCodeAt(0) <= 31 || c === "\u2028" || c.charCodeAt(0) >= 65534,
      ))
  )
    throw new Error("Invalid DOCX hyperlink display text");
}

export interface EditState {
  revision: number;
  readOnlyReason?: string;
  defaultTabStop: number;
  compositionId: number | null;
  drawingGestureId: number | null;
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
    preview: {
      family: string;
      size: number;
      color: string;
      bold: boolean;
      italic: boolean;
      underline: boolean;
      strike: boolean;
    } | null;
  }[];
}
