import type { ChartSettings } from "@open-document/wasm/abi/chart";
import type { MathFormula } from "@open-document/wasm/abi/math";
export type { MathExpression, MathFormula } from "@open-document/wasm/abi/math";
import type { ShapeBatch } from "./foundation.js";
import type { TabStop, DocxPageBorders } from "./docx-format.js";
import type { ParagraphFrame } from "./preview-frame.js";
import { record } from "@open-document/wasm/abi/validation";
import type { DocxFlowNote } from "./preview-notes.js";
import type { BasicDrawingShape } from "./preview-shape.js";
import type { DocxFlowTable } from "./preview-table.js";
import type { DocxSectionBreak } from "./docx-sections.js";
export type { DocxSectionBreak } from "./docx-sections.js";
import type { ParagraphNumbering } from "./preview-numbering.js";
import type { DrawingBatch } from "@open-document/wasm/abi/drawing";
import type { DocxCommentLayout } from "./docx-comments.js";
import type { DocxCellMargins } from "./docx-table.js";
import type { DocxColumns } from "./docx-columns.js";
import type { DocxSelectionView } from "./docx-hit.js";

export type { TextStyle } from "@open-document/wasm/abi/shape";
import type { TextStyle } from "@open-document/wasm/abi/shape";

export interface DocxFlow {
  sectionBreaks: DocxSectionBreak[];
  endnotesAt: "sectEnd" | "docEnd";
  footnotesAt: "pageBottom" | "beneathText";
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
    frame?: ParagraphFrame;
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
        | `NOTEREF:${string}`
        | `SEQ:${string}`
        | `CITATION:${string}`
        | `NOTE:${"footnote" | "endnote"}:${string}`
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
      numbering?: ParagraphNumbering | null;
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
  headers: Record<string, Pick<DocxFlow, "paragraphs" | "tables">>;
  headerDistance: number;
  footers: Record<string, Pick<DocxFlow, "paragraphs" | "tables">>;
  footerDistance: number;
  notes: DocxFlowNote[];
  differentFirst: boolean;
  differentEven: boolean;
  tables: DocxFlowTable[];
}

export interface DrawingFrame {
  width: number;
  height: number;
  /** Left, top, right and bottom inline layout extents, in points. */
  effectExtent: [number, number, number, number];
  anchor: DrawingAnchor | null;
  content:
    | { kind: "picture"; key: string; crop: number[] }
    | { kind: "math"; math: MathFormula }
    | { kind: "chart"; chart: ChartSettings }
    | {
        kind: "metafile";
        metafile: { identity: string; text: string; images: string[] };
      }
    | ({ kind: "shape" } & BasicDrawingShape)
    | {
        kind: "textBox";
        shape: BasicDrawingShape & { preset: "rect" | "ellipse" };
        text: {
          paragraphs: DocxFlow["paragraphs"];
          insets: number[];
          anchor: "t" | "ctr" | "b";
          wrap: boolean;
          clip: boolean;
          flowFrames: [number, number][];
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
  selectionView?: DocxSelectionView;
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

export type LayoutPreparation = PageLayout | { missingImages: string[] };

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
