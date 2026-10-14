import type { ShapeBatch } from "./foundation.js";
import { record, glyphs } from "./validation.js";

export interface TextStyle {
  font: string;
  size: number;
  color: string;
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

export interface PageLayout {
  id: number;
  revision: number;
  shapedParagraphs: number;
  reusedParagraphs: number;
  reflowedPages: number;
  reusedPages: number;
  profile: Record<string, string>;
  pages: PageFrame[];
  diagnostics: string[];
  outlines: ShapeBatch["outlines"];
  fonts: ShapeBatch["fonts"];
}

export interface PageFrame {
  width: number;
  height: number;
  borders: { x: number; y: number; width: number; height: number }[];
  fills: {
    x: number;
    y: number;
    width: number;
    height: number;
    color: string;
  }[];
  lines: {
    paragraph: number;
    container: number;
    baseLevel: number;
    text: string;
    start: number;
    end: number;
    x: number;
    areaX: number;
    areaWidth: number;
    y: number;
    width: number;
    height: number;
    clip: boolean;
    readOnlyReason: string;
    carets: ShapeBatch["carets"];
    images: (InlineImage & { x: number; y: number })[];
    runs: {
      start: number;
      sources: { node: number; start: number; end: number; offset: number }[];
      color: string;
      size: number;
      text: string;
      glyphs: ShapeBatch["glyphs"];
      bidi: ShapeBatch["runs"];
      x: number;
      baseline: number;
    }[];
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
        "before",
        "after",
        "left",
        "right",
        "first",
      ],
      ["align", "readOnlyReason"],
    );
    const spacing = fields(paragraph.line, ["value"], ["rule"]);
    if (
      typeof paragraph.nominalSize !== "number" ||
      paragraph.nominalSize <= 0 ||
      paragraph.nominalSize > 1024
    )
      throw new Error("Invalid nominal paragraph font size");
    if (!["auto", "exact", "atLeast"].includes(String(spacing.rule)))
      throw new Error("Invalid line spacing rule");
    if (typeof paragraph.pageBreakBefore !== "boolean")
      throw new Error("Invalid paragraph flags");
    for (const value of entries(paragraph.spans)) {
      const span = fields(value, ["node"], ["text"]);
      fields(span.style, ["size"], ["font", "color"]);
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
  const layout = fields(value, ["revision", "id"]);
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
  for (const value of entries(layout.outlines))
    fields(value, [], ["key", "path"]);
  for (const value of entries(layout.fonts))
    fields(
      value,
      ["face", "upem", "ascent", "descent", "capHeight", "italicAngle"],
      ["identity", "variation", "sha256"],
    );
  const pages = entries(layout.pages);
  if (pages.length === 0) throw new Error("Layout has no pages");
  if (
    Number(counts.reflowedPages) + Number(counts.reusedPages) !==
    pages.length
  )
    throw new Error("Invalid page reuse counts");
  for (const value of pages) {
    const page = fields(value, ["width", "height"]);
    for (const value of entries(page.fills))
      fields(value, ["x", "y", "width", "height"], ["color"]);
    for (const value of entries(page.borders))
      fields(value, ["x", "y", "width", "height"]);
    for (const value of entries(page.lines)) {
      const line = fields(
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
      if (typeof line.clip !== "boolean")
        throw new Error("Invalid line clipping");
      for (const value of entries(line.carets))
        fields(value, ["offset", "before", "after"]);
      for (const value of entries(line.images))
        fields(value, ["x", "y", "width", "height"], ["key"]);
      for (const value of entries(line.runs)) {
        const run = fields(
          value,
          ["start", "x", "baseline", "size"],
          ["color", "text"],
        );
        glyphs(run.glyphs);
        for (const value of entries(run.sources))
          fields(value, ["node", "start", "end", "offset"]);
        for (const value of entries(run.bidi))
          fields(
            value,
            ["start", "end", "level", "font"],
            ["script", "language"],
          );
      }
    }
  }
  return value as PageLayout;
}
