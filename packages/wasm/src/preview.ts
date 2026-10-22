import { checkChartSettings, type ChartSettings } from "./chart.js";
import { checkMathContent, type MathFormula } from "./math.js";
export type { MathExpression, MathFormula } from "./math.js";
import type { ShapeBatch } from "./foundation.js";
import {
  checkTabStops,
  type TabStop,
  checkPageBorders,
  type DocxPageBorders,
} from "./docx-format.js";
import { record } from "./validation.js";
import { drawingBatch, type DrawingBatch } from "./drawing.js";
import { docxCommentLayout, type DocxCommentLayout } from "./docx-comments.js";
import {
  checkDocxCellMargins,
  checkDocxBorders,
  type DocxCellMargins,
  type DocxBorderStyle,
} from "./docx-table.js";

export interface TextStyle {
  font: string;
  size: number;
  color: string;
  underline: boolean;
  strike: boolean;
  highlight: string;
  script: "baseline" | "superscript" | "subscript";
  spacing: number;
}

export interface DocxFlow {
  columns: DocxColumns;
  pageNumbering: { start: number; format: string };
  bookmarks: Record<string, [number, number, number, number]>;
  outlineLevels: Record<string, number>;
  pageBorders: DocxPageBorders;
  background: string;
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
      drawing: DrawingFrame | null;
      field:
        | ""
        | "PAGE"
        | "NUMPAGES"
        | `PAGEREF:${string}`
        | `REF:${string}`
        | `SEQ:${string}`
        | `${"PAGE" | "NUMPAGES"}:${"decimal" | "decimalZero" | "lowerLetter" | "upperLetter" | "lowerRoman" | "upperRoman"}`;
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
    keepLines: boolean;
    keepNext: boolean;
    widowControl: boolean;
    readOnlyReason: string;
  }[];
  diagnostics: string[];
  headers: Record<string, DocxFlow["paragraphs"]>;
  headerDistance: number;
  footers: Record<string, DocxFlow["paragraphs"]>;
  footerDistance: number;
  differentFirst: boolean;
  differentEven: boolean;
  tables: {
    autoFit: boolean;
    preferredWidth: { value: number; percent: boolean };
    preferredWidths: DocxFlow["tables"][number]["preferredWidth"][][];
    id: number;
    beforeParagraph: number;
    rows: DocxFlow["paragraphs"][][];
    widths: number[];
    align: string;
    borders: { horizontal: DocxBorderStyle[][]; vertical: DocxBorderStyle[][] };
    margins: DocxCellMargins[][];
    heights: number[];
    exactHeights: boolean[];
    splitRows: boolean[];
    fills: string[][];
    verticalAligns: ("top" | "center" | "bottom")[][];
    headerRows: number;
  }[];
}

export interface DrawingFrame {
  width: number;
  height: number;
  anchor: DrawingAnchor | null;
  content:
    | { kind: "picture"; key: string; crop: number[] }
    | { kind: "math"; math: MathFormula }
    | { kind: "chart"; chart: ChartSettings }
    | {
        kind: "shape";
        preset: "rect" | "ellipse" | "line";
        fill: string;
        stroke: string;
        lineWidth: number;
      }
    | {
        kind: "textBox";
        shape: {
          preset: "rect" | "ellipse";
          fill: string;
          stroke: string;
          lineWidth: number;
        };
        text: {
          paragraphs: DocxFlow["paragraphs"];
          insets: number[];
          anchor: "t" | "ctr" | "b";
          wrap: boolean;
          clip: boolean;
        };
      };
}

export type DrawingAxis =
  | { relativeTo: string; offset: number; align: null }
  | { relativeTo: string; offset: null; align: string };
export interface DrawingAnchor {
  horizontal: DrawingAxis;
  vertical: DrawingAxis;
  behind: boolean;
  order: number;
  wrapping: "none" | "topBottom" | "square";
  wrapSide: "bothSides" | "left" | "right" | "largest";
  distance: DocxCellMargins;
}

export function checkDrawingAnchor(value: unknown): void {
  if (value === null) return;
  const anchor = record(value);
  if (
    anchor.wrapping !== "none" &&
    anchor.wrapping !== "topBottom" &&
    anchor.wrapping !== "square"
  )
    throw new Error("Invalid floating image wrapping");
  if (
    typeof anchor.wrapSide !== "string" ||
    !["bothSides", "left", "right", "largest"].includes(anchor.wrapSide)
  )
    throw new Error("Invalid floating image wrap side");
  if (anchor.wrapping !== "square" && anchor.wrapSide !== "bothSides")
    throw new Error("Wrap side requires square wrapping");
  const distance = record(anchor.distance);
  if (
    !["top", "right", "bottom", "left"].every(
      (key) =>
        typeof distance[key] === "number" &&
        Number.isFinite(distance[key]) &&
        Number(distance[key]) >= 0 &&
        Number(distance[key]) <= 14400,
    )
  )
    throw new Error("Invalid floating image text distance");
  if (
    typeof anchor.behind !== "boolean" ||
    !Number.isSafeInteger(anchor.order) ||
    Number(anchor.order) < 0 ||
    Number(anchor.order) > 4294967295
  )
    throw new Error("Invalid floating image layer");
  for (const key of ["horizontal", "vertical"] as const) {
    const axis = record(anchor[key]);
    const references =
      key === "horizontal"
        ? ["page", "margin", "column"]
        : ["page", "margin", "paragraph"];
    const alignments =
      key === "horizontal"
        ? ["left", "center", "right"]
        : ["top", "center", "bottom"];
    if (
      typeof axis.relativeTo !== "string" ||
      !references.includes(axis.relativeTo) ||
      !(
        (axis.align === null &&
          typeof axis.offset === "number" &&
          Number.isFinite(axis.offset) &&
          Math.abs(axis.offset) <= 14400) ||
        (axis.offset === null &&
          typeof axis.align === "string" &&
          alignments.includes(axis.align))
      )
    )
      throw new Error("Invalid floating image position");
  }
}

export interface PageLayout extends DrawingBatch {
  comments: DocxCommentLayout;
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

function preferredWidth(value: unknown): void {
  const width = record(value);
  if (
    Object.keys(width).length !== 2 ||
    Object.keys(width).some((key) => !["value", "percent"].includes(key)) ||
    typeof width.percent !== "boolean" ||
    typeof width.value !== "number" ||
    !Number.isFinite(width.value) ||
    width.value < 0 ||
    width.value > (width.percent ? 1 : 14400)
  )
    throw new Error("Invalid table width preference");
}

export function docxFlow(value: unknown): DocxFlow {
  const flow = fields(value, ["revision", "headerDistance", "footerDistance"]);
  const bookmarks = record(flow.bookmarks);
  if (
    Object.entries(record(flow.outlineLevels)).some(
      ([id, level]) =>
        !/^(0|[1-9][0-9]*)$/u.test(id) ||
        !Number.isSafeInteger(Number(id)) ||
        !Number.isInteger(level) ||
        Number(level) < 0 ||
        Number(level) > 8,
    )
  )
    throw new Error("Invalid document outline levels");
  if (
    Object.keys(bookmarks).length > 4096 ||
    Object.entries(bookmarks).some(
      ([name, position]) =>
        !name.length ||
        !Array.isArray(position) ||
        position.length !== 4 ||
        !position.every((value) => Number.isSafeInteger(value) && value >= 0),
    )
  )
    throw new Error("Invalid document field targets");
  checkDocxColumns(fields(flow.columns, ["count", "gap"]));
  const numbering = fields(flow.pageNumbering, ["start"], ["format"]);
  if (
    !Number.isInteger(numbering.start) ||
    Number(numbering.start) < 0 ||
    Number(numbering.start) > 4294967295 ||
    ![
      "decimal",
      "decimalZero",
      "lowerLetter",
      "upperLetter",
      "lowerRoman",
      "upperRoman",
    ].includes(String(numbering.format))
  )
    throw new Error("Invalid document page numbering");
  if (flow.pageBorders === null)
    throw new Error("Missing document page borders");
  checkPageBorders(flow.pageBorders);
  if (
    typeof flow.background !== "string" ||
    !/^[0-9a-f]{6}$/iu.test(flow.background)
  )
    throw new Error("Invalid document page background");
  if (
    typeof flow.differentFirst !== "boolean" ||
    typeof flow.differentEven !== "boolean"
  )
    throw new Error("Invalid running area flags");
  if (typeof flow.additiveSpacing !== "boolean")
    throw new Error("Invalid paragraph spacing mode");
  fields(flow.page, ["width", "height", "top", "right", "bottom", "left"]);
  diagnostics(flow.diagnostics);
  function checkParagraph(value: unknown, inTextBox = false): void {
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
        ["size", "spacing"],
        ["font", "color", "highlight", "script"],
      );
      if (
        typeof style.underline !== "boolean" ||
        typeof style.strike !== "boolean" ||
        Math.abs(Number(style.spacing)) > 1584 ||
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
      typeof paragraph.keepLines !== "boolean" ||
      typeof paragraph.keepNext !== "boolean" ||
      typeof paragraph.widowControl !== "boolean" ||
      typeof paragraph.rtl !== "boolean" ||
      typeof paragraph.expandSoftBreak !== "boolean"
    )
      throw new Error("Invalid paragraph flags");
    if (
      inTextBox &&
      (paragraph.pageBreakBefore || paragraph.marker !== undefined)
    )
      throw new Error("Text box lists and page breaks require support");
    for (const value of entries(paragraph.spans)) {
      const span = fields(value, ["node"], ["text", "field"]);
      if (
        typeof span.field !== "string" ||
        !/^(?:(?:PAGE|NUMPAGES)(?::(?:decimal|decimalZero|lowerLetter|upperLetter|lowerRoman|upperRoman))?|PAGEREF:[A-Za-z_][A-Za-z0-9_]{0,39}(?::(?:decimal|decimalZero|lowerLetter|upperLetter|lowerRoman|upperRoman))?(?::hyperlink)?(?::relative)?|REF:[A-Za-z_][A-Za-z0-9_]{0,39}(?::hyperlink)?|SEQ:[_\p{ID_Start}][_\p{ID_Continue}]{0,39}(?::(?:decimal|lowerLetter|upperLetter|lowerRoman|upperRoman))?(?::(?:repeat|restart=[0-9]{1,10}))?(?::heading=[1-9])?)?$/u.test(
          span.field,
        ) ||
        (span.field.startsWith("SEQ:") &&
          (span.field.split(":")[1]!.length > 40 ||
            Number(span.field.split("restart=")[1]?.split(":")[0] ?? 0) >
              2147483647)) ||
        (span.field !== "" && span.drawing !== null)
      )
        throw new Error("Invalid running field");
      const style = fields(
        span.style,
        ["size", "spacing"],
        ["font", "color", "highlight", "script"],
      );
      if (
        typeof style.underline !== "boolean" ||
        typeof style.strike !== "boolean" ||
        Math.abs(Number(style.spacing)) > 1584 ||
        !["baseline", "superscript", "subscript"].includes(String(style.script))
      )
        throw new Error("Invalid preview text decoration");
      if (span.drawing !== null) {
        if (inTextBox)
          throw new Error("Nested text box drawings require support");
        const image = fields(span.drawing, ["width", "height"], []);
        checkDrawingAnchor(image.anchor);
        const content = fields(image.content, [], ["kind"]);
        const positive = Number(image.width) > 0 && Number(image.height) > 0;
        if (
          Number(image.width) < 0 ||
          Number(image.height) < 0 ||
          Number(image.width) > 14400 ||
          Number(image.height) > 14400
        )
          throw new Error("Invalid drawing dimensions");
        if (content.kind === "chart") {
          if (Number(image.width) < 180 || Number(image.height) < 150)
            throw new Error("Invalid chart dimensions");
          checkChartSettings(content.chart);
          continue;
        }
        if (content.kind === "math") {
          if (image.anchor !== null)
            throw new Error("Mathematical expression must remain inline");
          checkMathContent(content.math);
          continue;
        }
        if (content.kind === "shape" || content.kind === "textBox") {
          const shape = fields(
            content.kind === "textBox" ? content.shape : content,
            ["lineWidth"],
            ["preset", "fill", "stroke"],
          );
          if (
            !["rect", "ellipse", "line"].includes(String(shape.preset)) ||
            !(
              positive ||
              (shape.preset === "line" &&
                (Number(image.width) > 0 || Number(image.height) > 0))
            ) ||
            ![shape.fill, shape.stroke].every(
              (value) =>
                typeof value === "string" &&
                /^(?:[a-fA-F0-9]{6})?$/.test(value),
            ) ||
            Number(shape.lineWidth) < 0 ||
            Number(shape.lineWidth) > 1584
          )
            throw new Error("Invalid basic drawing shape");
          if (content.kind === "textBox") {
            const text = fields(content.text, [], ["anchor"]);
            const paragraphs = entries(text.paragraphs);
            if (
              shape.preset === "line" ||
              !["t", "ctr", "b"].includes(String(text.anchor)) ||
              typeof text.wrap !== "boolean" ||
              typeof text.clip !== "boolean" ||
              !Array.isArray(text.insets) ||
              text.insets.length !== 4 ||
              text.insets.some(
                (v: unknown) =>
                  typeof v !== "number" ||
                  !Number.isFinite(v) ||
                  v < 0 ||
                  v > 14400,
              ) ||
              paragraphs.length < 1 ||
              paragraphs.length > 256
            )
              throw new Error("Invalid drawing text box");
            let units = 0;
            for (const value of paragraphs) {
              checkParagraph(value, true);
              const p = record(value);
              for (const value of entries(p.spans)) {
                const span = record(value);
                if (span.field !== "" || typeof span.text !== "string")
                  throw new Error("Invalid text box span");
                units += span.text.length;
              }
            }
            if (units > 32767) throw new Error("Text box exceeds text budget");
          }
          continue;
        }
        if (
          content.kind !== "picture" ||
          !positive ||
          typeof content.key !== "string" ||
          !content.key.length ||
          content.key.length > 4096
        )
          throw new Error("Invalid picture drawing");
        const crop = content.crop;
        if (
          !Array.isArray(crop) ||
          crop.length !== 4 ||
          crop.some(
            (v: unknown) =>
              typeof v !== "number" || !Number.isFinite(v) || v < 0 || v >= 1,
          ) ||
          crop[0] + crop[2] >= 1 ||
          crop[1] + crop[3] >= 1
        )
          throw new Error("Invalid inline image crop");
      }
    }
  }
  const paragraphs = entries(flow.paragraphs);
  for (const value of paragraphs) checkParagraph(value);
  for (const stories of [record(flow.headers), record(flow.footers)]) {
    for (const [key, story] of Object.entries(stories)) {
      if (!["default", "first", "even"].includes(key))
        throw new Error("Invalid running variant");
      for (const value of entries(story)) checkParagraph(value);
    }
  }
  let previousPosition = 0;
  for (const value of entries(flow.tables)) {
    const table = fields(value, ["id", "beforeParagraph"], ["align"]);
    if (typeof table.autoFit !== "boolean")
      throw new Error("Invalid table sizing preferences");
    preferredWidth(table.preferredWidth);
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
    const rows = entries(table.rows),
      verticalAligns = entries(table.verticalAligns);
    const preferred = entries(table.preferredWidths);
    if (
      preferred.length !== rows.length ||
      preferred.some(
        (row, r) => entries(row).length !== entries(rows[r]).length,
      )
    )
      throw new Error("Invalid preferred cell widths");
    for (const row of preferred)
      for (const width of entries(row)) preferredWidth(width);
    const exactHeights = entries(table.exactHeights);
    if (
      exactHeights.length !== rows.length ||
      exactHeights.some((value) => typeof value !== "boolean")
    )
      throw new Error("Invalid row height rules");
    const splitRows = entries(table.splitRows);
    if (
      splitRows.length !== rows.length ||
      splitRows.some((value) => typeof value !== "boolean")
    )
      throw new Error("Invalid row split settings");
    const margins = entries(table.margins);
    if (
      !Number.isSafeInteger(table.headerRows) ||
      Number(table.headerRows) < 0 ||
      Number(table.headerRows) > rows.length
    )
      throw new Error("Invalid table header count");
    if (
      margins.length !== rows.length ||
      margins.some((row, r) => entries(row).length !== entries(rows[r]).length)
    )
      throw new Error("Invalid cell margin dimensions");
    for (const row of margins)
      for (const value of entries(row)) checkDocxCellMargins(value);
    if (
      verticalAligns.length !== rows.length ||
      verticalAligns.some((row, r) => {
        const values = entries(row);
        return (
          values.length !== entries(rows[r]).length ||
          values.some(
            (value) =>
              typeof value !== "string" ||
              !["top", "center", "bottom"].includes(value),
          )
        );
      })
    )
      throw new Error("Invalid cell vertical alignments");
    if (
      !entries(table.widths).every(
        (item) => typeof item === "number" && Number.isFinite(item),
      )
    )
      throw new Error("Invalid table properties");
    const borders = record(table.borders),
      columns = entries(table.widths).length;
    for (const [key, height, width] of [
      ["horizontal", rows.length + 1, columns],
      ["vertical", rows.length, columns + 1],
    ] as const) {
      const edges = entries(borders[key]);
      if (
        edges.length !== height ||
        edges.some((row) => entries(row).length !== width)
      )
        throw new Error("Invalid border grid");
      for (const row of edges)
        for (const edge of entries(row)) {
          if (edge === null) throw new Error("Invalid border grid edge");
          checkDocxBorders({ top: edge }, false);
        }
    }
    for (const row of entries(table.rows))
      for (const cell of entries(row))
        for (const value of entries(cell)) checkParagraph(value);
  }
  return value as DocxFlow;
}

export function pageLayout(value: unknown): PageLayout {
  const drawing = drawingBatch(value);
  const layout = fields(value, ["revision", "id"]);
  docxCommentLayout(layout.comments, drawing.regions);
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
import { checkDocxColumns, type DocxColumns } from "./docx-columns.js";
