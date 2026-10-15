import type { ShapeBatch } from "./foundation.js";
import { checkTabStops, type TabStop } from "./docx-format.js";
import { record } from "./validation.js";
import { drawingBatch, type DrawingBatch } from "./drawing.js";

export interface TextStyle {
  font: string;
  size: number;
  color: string;
  underline: boolean;
  strike: boolean;
  highlight: string;
  script: "baseline" | "superscript" | "subscript";
}

export interface DocxFlow {
  additiveSpacing: boolean;
  revision: number;
  page: {
    width: number;
    height: number;
    top: number;
    right: number;
    bottom: number;
    left: number;
  };
  paragraphs: {
    id: number;
    container: number;
    nominalSize: number;
    defaultTab: number;
    tabs: TabStop[];
    decimalSymbol: string;
    expandSoftBreak: boolean;
    spans: {
      node: number;
      text: string;
      style: TextStyle;
      image: InlineImage | null;
    }[];
    before: number;
    after: number;
    line: { rule: "auto" | "exact" | "atLeast"; value: number };
    left: number;
    right: number;
    first: number;
    align: string;
    rtl: boolean;
    marker?: {
      text: string;
      style: TextStyle;
      align: "left" | "right" | "center";
      suffix: "tab" | "space" | "nothing";
    };
    pageBreakBefore: boolean;
    readOnlyReason: string;
  }[];
  diagnostics: string[];
  headers: DocxFlow["paragraphs"][];
  headerDistance: number;
  tables: {
    id: number;
    beforeParagraph: number;
    rows: DocxFlow["paragraphs"][][];
    widths: number[];
    align: string;
    borders: boolean;
    padding: number;
    verticalPadding: number;
    heights: number[];
    fills: string[][];
  }[];
}

export interface InlineImage {
  key: string;
  width: number;
  height: number;
}

export interface PageLayout extends DrawingBatch {
  id: number;
  revision: number;
  shapedParagraphs: number;
  reusedParagraphs: number;
  reflowedPages: number;
  reusedPages: number;
  profile: Record<string, string>;
  semantics: SemanticPage[];
  diagnostics: string[];
  fonts: ShapeBatch["fonts"];
}

export interface SemanticPage {
  lines: {
    paragraph: number;
    container: number;
    baseLevel: number;
    text: string;
    marker?: string;
    start: number;
    end: number;
    x: number;
    areaX: number;
    areaWidth: number;
    y: number;
    width: number;
    height: number;
    readOnlyReason: string;
  }[];
}

function fields(
  value: unknown,
  numbers: string[],
  strings: string[] = [],
): Record<string, unknown> {
  const object = record(value);
  if (
    !numbers.every(
      (key) => typeof object[key] === "number" && Number.isFinite(object[key]),
    ) ||
    !strings.every((key) => typeof object[key] === "string")
  )
    throw new Error("Invalid preview fields returned by Wasm");
  return object;
}

function entries(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw new Error("Invalid preview array");
  return value;
}

function diagnostics(value: unknown): void {
  if (!entries(value).every((entry) => typeof entry === "string"))
    throw new Error("Invalid preview diagnostics");
}

export function docxFlow(value: unknown): DocxFlow {
  const flow = fields(value, ["revision", "headerDistance"]);
  if (typeof flow.additiveSpacing !== "boolean")
    throw new Error("Invalid paragraph spacing mode");
  fields(flow.page, ["width", "height", "top", "right", "bottom", "left"]);
  diagnostics(flow.diagnostics);
  function paragraph(value: unknown): void {
    const paragraph = fields(
      value,
      [
        "id",
        "container",
        "nominalSize",
        "defaultTab",
        "before",
        "after",
        "left",
        "right",
        "first",
      ],
      ["align", "readOnlyReason", "decimalSymbol"],
    );
    checkTabStops(paragraph.tabs);
    if (paragraph.marker !== undefined) {
      const marker = fields(paragraph.marker, [], ["text", "align", "suffix"]);
      if (
        !["left", "right", "center"].includes(String(marker.align)) ||
        !["tab", "space", "nothing"].includes(String(marker.suffix))
      )
        throw new Error("Invalid paragraph marker");
      const style = fields(
        marker.style,
        ["size"],
        ["font", "color", "highlight", "script"],
      );
      if (
        typeof style.underline !== "boolean" ||
        typeof style.strike !== "boolean" ||
        !["baseline", "superscript", "subscript"].includes(String(style.script))
      )
        throw new Error("Invalid paragraph marker style");
    }
    const spacing = fields(paragraph.line, ["value"], ["rule"]);
    if (
      typeof paragraph.nominalSize !== "number" ||
      paragraph.nominalSize <= 0 ||
      paragraph.nominalSize > 1024
    )
      throw new Error("Invalid nominal paragraph font size");
    if (!["auto", "exact", "atLeast"].includes(String(spacing.rule)))
      throw new Error("Invalid line spacing rule");
    if (
      typeof paragraph.pageBreakBefore !== "boolean" ||
      typeof paragraph.rtl !== "boolean" ||
      typeof paragraph.expandSoftBreak !== "boolean"
    )
      throw new Error("Invalid paragraph flags");
    for (const value of entries(paragraph.spans)) {
      const span = fields(value, ["node"], ["text"]);
      const style = fields(
        span.style,
        ["size"],
        ["font", "color", "highlight", "script"],
      );
      if (
        typeof style.underline !== "boolean" ||
        typeof style.strike !== "boolean" ||
        !["baseline", "superscript", "subscript"].includes(String(style.script))
      )
        throw new Error("Invalid preview text decoration");
      if (span.image !== null) fields(span.image, ["width", "height"], ["key"]);
    }
  }
  const paragraphs = entries(flow.paragraphs);
  for (const value of paragraphs) paragraph(value);
  for (const header of entries(flow.headers))
    for (const value of entries(header)) paragraph(value);
  let previousPosition = 0;
  for (const value of entries(flow.tables)) {
    const table = fields(
      value,
      ["id", "beforeParagraph", "padding", "verticalPadding"],
      ["align"],
    );
    if (
      typeof table.beforeParagraph !== "number" ||
      !Number.isInteger(table.beforeParagraph) ||
      table.beforeParagraph < previousPosition ||
      table.beforeParagraph > paragraphs.length
    )
      throw new Error("Invalid table body position");
    previousPosition = table.beforeParagraph;
    for (const height of entries(table.heights))
      if (typeof height !== "number" || !Number.isFinite(height))
        throw new Error("Invalid row height");
    for (const row of entries(table.fills)) diagnostics(row);
    if (
      typeof table.borders !== "boolean" ||
      !entries(table.widths).every(
        (item) => typeof item === "number" && Number.isFinite(item),
      )
    )
      throw new Error("Invalid table properties");
    for (const row of entries(table.rows))
      for (const cell of entries(row))
        for (const value of entries(cell)) paragraph(value);
  }
  return value as DocxFlow;
}

export function pageLayout(value: unknown): PageLayout {
  const drawing = drawingBatch(value);
  const layout = fields(value, ["revision", "id"]);
  if (
    !Number.isInteger(layout.id) ||
    Number(layout.id) <= 0 ||
    !Number.isInteger(layout.revision) ||
    Number(layout.revision) < 0
  )
    throw new Error("Invalid layout identity");
  const counts = fields(value, [
    "shapedParagraphs",
    "reusedParagraphs",
    "reflowedPages",
    "reusedPages",
  ]);
  if (
    ![
      counts.shapedParagraphs,
      counts.reusedParagraphs,
      counts.reflowedPages,
      counts.reusedPages,
    ].every(
      (count) =>
        typeof count === "number" &&
        Number.isInteger(count) &&
        count >= 0 &&
        count <= 2147483647,
    )
  )
    throw new Error("Invalid paragraph shaping counts");
  if (
    !Object.values(record(layout.profile)).every(
      (item) => typeof item === "string",
    )
  )
    throw new Error("Invalid font profile");
  diagnostics(layout.diagnostics);
  for (const value of entries(layout.fonts))
    fields(
      value,
      ["face", "upem", "ascent", "descent", "capHeight", "italicAngle"],
      ["identity", "variation", "sha256"],
    );
  if (
    Number(counts.reflowedPages) + Number(counts.reusedPages) !==
    drawing.regions.length
  )
    throw new Error("Invalid page reuse counts");
  const semantics = entries(layout.semantics);
  if (semantics.length !== drawing.regions.length)
    throw new Error("Invalid semantic page count");
  for (const value of semantics) {
    const page = record(value);
    for (const value of entries(page.lines)) {
      const line = record(value);
      if (line.marker !== undefined && typeof line.marker !== "string")
        throw new Error("Invalid semantic marker");
      fields(
        value,
        [
          "paragraph",
          "container",
          "baseLevel",
          "start",
          "end",
          "x",
          "areaX",
          "areaWidth",
          "y",
          "width",
          "height",
        ],
        ["text", "readOnlyReason"],
      );
    }
  }
  return value as PageLayout;
}
